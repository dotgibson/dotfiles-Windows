# ============================================================================
#  tests/Invoke-Validation.ps1  -  fast, dependency-free repo health gate.
#
#  Runs WITHOUT PSScriptAnalyzer or Pester (no PowerShell Gallery needed), so it
#  works in a locked-down/offline environment and as a pre-commit smoke test:
#    pwsh -NoProfile -File tests/Invoke-Validation.ps1
#
#  Checks:
#    1. every *.ps1 parses cleanly (real syntax/regression gate via the AST parser)
#    2. every *.json is well-formed and the package manifests have no dup entries
#    3. starship.toml parses as TOML (best-effort; skipped if no parser available)
#
#  Exit code is non-zero if anything fails, so CI and hooks can gate on it.
#  The richer lint (PSScriptAnalyzer) + behavioral tests (Pester) run in CI on a
#  Windows runner, where the Gallery is reachable — see .github/workflows/ci.yml.
# ============================================================================
[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$fail = 0
function Fail { param([string]$m) $script:fail++; Write-Host "  ✗ $m" -ForegroundColor Red }
function Pass { param([string]$m) Write-Host "  ✓ $m" -ForegroundColor Green }

# --- 1. PowerShell syntax (AST parse) -----------------------------------------
Write-Host 'PowerShell syntax:' -ForegroundColor Cyan
$ps1 = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.ps1 -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
foreach ($f in $ps1) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) {
        Fail "parse: $($f.FullName)"
        $errors | ForEach-Object { Write-Host "      $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor DarkRed }
    }
}
if ($script:fail -eq 0) { Pass "$($ps1.Count) script(s) parsed clean" }

# --- 2. JSON well-formedness + manifest integrity -----------------------------
Write-Host 'JSON / manifests:' -ForegroundColor Cyan
$preJson = $script:fail
Get-ChildItem -Path $RepoRoot -Recurse -Filter *.json -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | ForEach-Object {
        try { Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null }
        catch { Fail "json: $($_.FullName): $_" }
    }

$scoop = Join-Path $RepoRoot 'packages/scoopfile.json'
if (Test-Path $scoop) {
    $m = Get-Content $scoop -Raw | ConvertFrom-Json
    $dupApps = $m.apps.Name | Group-Object | Where-Object Count -gt 1
    if ($dupApps) { Fail "scoopfile.json duplicate apps: $($dupApps.Name -join ', ')" }
    $dupBkt = $m.buckets.Name | Group-Object | Where-Object Count -gt 1
    if ($dupBkt) { Fail "scoopfile.json duplicate buckets: $($dupBkt.Name -join ', ')" }
}
$wg = Join-Path $RepoRoot 'packages/winget.json'
if (Test-Path $wg) {
    $w = (Get-Content $wg -Raw | ConvertFrom-Json).packages
    $dupWg = $w | Group-Object | Where-Object Count -gt 1
    if ($dupWg) { Fail "winget.json duplicate ids: $($dupWg.Name -join ', ')" }
}
if ($script:fail -eq $preJson) { Pass 'all JSON valid; manifests have no duplicates' }

# --- 3. TOML (best-effort) ----------------------------------------------------
Write-Host 'TOML (best-effort):' -ForegroundColor Cyan
$toml = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.toml -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    $preToml = $script:fail
    foreach ($t in $toml) {
        $py = "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))"
        & python3 -c $py $t.FullName 2>$null
        if ($LASTEXITCODE -ne 0) { Fail "toml: $($t.FullName)" }
    }
    if ($script:fail -eq $preToml) { Pass "$($toml.Count) TOML file(s) checked" }
} else {
    Write-Host '  - skipped (no python tomllib available)' -ForegroundColor DarkGray
}

Write-Host ''
if ($script:fail) {
    Write-Host "VALIDATION FAILED ($script:fail issue(s))" -ForegroundColor Red
    exit 1
}
Write-Host 'VALIDATION PASSED' -ForegroundColor Green
exit 0
