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
    # Provenance: every app names a declared bucket and looks like a real app id,
    # so a typo'd entry fails here instead of only on a live box at install time.
    $declared = @($m.buckets.Name)
    foreach ($app in $m.apps) {
        if ($app.Name -notmatch '^[\w.+-]+$') { Fail "scoopfile.json odd app name: '$($app.Name)'" }
        if ($declared -notcontains $app.Source) { Fail "scoopfile.json app '$($app.Name)' references undeclared bucket '$($app.Source)'" }
    }
}
$wg = Join-Path $RepoRoot 'packages/winget.json'
if (Test-Path $wg) {
    $w = (Get-Content $wg -Raw | ConvertFrom-Json).packages
    $dupWg = $w | Group-Object | Where-Object Count -gt 1
    if ($dupWg) { Fail "winget.json duplicate ids: $($dupWg.Name -join ', ')" }
    # Provenance: winget ids are Publisher.Package (at least one dot, no spaces).
    foreach ($id in $w) {
        if ($id -notmatch '^[^\s.]+(\.[^\s.]+)+$') { Fail "winget.json malformed id: '$id'" }
    }
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

# --- 4. editorconfig basics (final newline, no trailing WS, LF endings) --------
# Enforces the shipped .editorconfig where it's cheap and unambiguous, so the
# whole fleet's formatting can't silently drift. Dependency-free (no editorconfig
# binary): we encode the few rules that matter here.
#   • every text file ends with a newline           (insert_final_newline = true)
#   • no trailing whitespace, except *.md            (trim_trailing_whitespace)
#   • LF line endings, except *.cmd/*.bat            (end_of_line = lf|crlf)
Write-Host 'editorconfig (final newline / trailing WS / LF):' -ForegroundColor Cyan
$preEc = $script:fail
$textExt = '.ps1', '.psm1', '.psd1', '.lua', '.json', '.yml', '.yaml', '.toml', '.md'
$crlfOk  = '.cmd', '.bat'
$ecFiles = Get-ChildItem -Path $RepoRoot -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        ($_.Extension -in $textExt -or $_.Name -in '.editorconfig', '.gitignore', '.gitignore_global', '.gitconfig', 'config')
    }
foreach ($f in $ecFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -eq 0) { continue }                       # empty file: nothing to check
    if ($bytes[-1] -ne 0x0A) { Fail "no final newline: $($f.FullName)" }
    if ($f.Extension -notin $crlfOk -and ($bytes -contains 0x0D)) {
        Fail "CRLF line ending (want LF): $($f.FullName)"
    }
    if ($f.Extension -ne '.md') {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text -split "`n" | Where-Object { $_ -match '[ \t]+\r?$' }) {
            Fail "trailing whitespace: $($f.FullName)"
        }
    }
}
if ($script:fail -eq $preEc) { Pass "$($ecFiles.Count) file(s) match editorconfig basics" }

Write-Host ''
if ($script:fail) {
    Write-Host "VALIDATION FAILED ($script:fail issue(s))" -ForegroundColor Red
    exit 1
}
Write-Host 'VALIDATION PASSED' -ForegroundColor Green
exit 0
