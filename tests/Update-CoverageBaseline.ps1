# ============================================================================
#  tests/Update-CoverageBaseline.ps1  -  regenerate coverage-baseline.json (B5).
#  Run on a box where Pester (the pinned version) is installed:
#      .\tests\Update-CoverageBaseline.ps1
#      .\tests\Update-CoverageBaseline.ps1 -DryRun            # print, write nothing
#      .\tests\Update-CoverageBaseline.ps1 -CoveragePercentTarget 90
#
#  Runs the SAME Pester configuration ci.yml gates on, captures the resulting
#  test-case count as the anti-deletion FLOOR, and records the coverage target.
#  Commit the resulting coverage-baseline.json — it is the versioned source of
#  truth for those two numbers (replacing the literals that used to live in
#  ci.yml). Re-run it whenever you intentionally remove tests.
#
#  The test-FILE count is NOT recorded here: CI auto-derives it from the
#  tests/**/*.Tests.ps1 glob and asserts an exact match (issue #29), so there is
#  no file number to maintain. The coverage % target is a deliberate quality BAR,
#  not an auto-ratcheted floor: it is preserved across runs (or overridden with
#  -CoveragePercentTarget) so a one-line refactor that nudges coverage can't
#  silently raise the bar and break the next build. Only the test-case FLOOR
#  tracks the real suite.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$DryRun,
    [double]$CoveragePercentTarget,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'CoverageGate.ps1')

if ($Help) {
    @(
        'Update-CoverageBaseline.ps1 - regenerate coverage-baseline.json (B5)'
        ''
        'USAGE'
        '  .\tests\Update-CoverageBaseline.ps1 [-DryRun] [-CoveragePercentTarget <n>] [-Help]'
        ''
        'OPTIONS'
        '  -DryRun                  Print the resolved baseline and write nothing.'
        '  -CoveragePercentTarget   Override the coverage bar (default: keep the'
        '                           current baseline value, or 85 if none exists).'
        '  -Help                    Show this help and exit.'
        ''
        'NOTES'
        '  Run on a box with the pinned Pester installed. Commit the result.'
    ) | ForEach-Object { Write-Host $_ }
    return
}

$baselinePath = Join-Path $here 'coverage-baseline.json'

# Default the target to the existing baseline's value (preserve the bar) unless
# the caller overrode it — so a routine "I added tests" refresh never moves it.
if (-not $PSBoundParameters.ContainsKey('CoveragePercentTarget')) {
    $CoveragePercentTarget = 85
    if (Test-Path $baselinePath) {
        try { $CoveragePercentTarget = (Read-CoverageBaseline (Get-Content $baselinePath -Raw)).CoveragePercentTarget }
        catch { Write-Warning "existing baseline unreadable, defaulting target to 85: $($_.Exception.Message)" }
    }
}

# Run the SAME configuration ci.yml uses, so the captured floors match what the
# gate will see. (Coverage paths are duplicated from ci.yml intentionally; the
# Repo.Tests "ci.yml and baseline agree" check guards against the two drifting.)
# Pin to the CI Pester version when the env var is set (CI always sets it); fall
# back to whatever Pester is installed for an ad-hoc local refresh.
if ($env:PESTER_VERSION) {
    Import-Module Pester -RequiredVersion $env:PESTER_VERSION -ErrorAction Stop
} else {
    Import-Module Pester -ErrorAction Stop
}
$repoRoot = Split-Path -Parent $here
$testPath = Join-Path $repoRoot 'tests'
$cfg = New-PesterConfiguration
$cfg.Run.Path = $testPath
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'None'
$cfg.CodeCoverage.Enabled = $true
$cfg.CodeCoverage.Path = @(
    (Join-Path $repoRoot 'powershell/core/05-lib.ps1')
    (Join-Path $repoRoot 'powershell/Dotfiles/Wsl.Helpers.ps1')
    (Join-Path $repoRoot 'powershell/Dotfiles/Doctor.Helpers.ps1')
    (Join-Path $repoRoot 'powershell/Dotfiles/Help.Helpers.ps1')
    (Join-Path $repoRoot 'powershell/Dotfiles/Modules.Helpers.ps1')
)
$r = Invoke-Pester -Configuration $cfg

# Refuse to write a baseline CI would reject — a generator that ratchets the
# floor down from a PARTIAL discovery (a test file that failed to load shows up
# as fewer containers) or writes a target the suite doesn't actually meet is
# worse than no refresh. Validate the same things ci.yml gates on, first:
if ($r.FailedCount -gt 0) {
    throw "$($r.FailedCount) test(s) failed — fix the suite before refreshing the baseline."
}
# (1) Pester discovered EXACTLY the on-disk *.Tests.ps1 set (mirrors the CI
#     auto-derive). A mismatch means a suite didn't load — its tests would be
#     missing from the captured floor.
$expectedFiles = @(Get-ChildItem $testPath -Recurse -File -Filter *.Tests.ps1 -ErrorAction Stop).Count
if ($r.Containers.Count -ne $expectedFiles) {
    throw "Pester discovered $($r.Containers.Count) test file(s) but tests/ has $expectedFiles *.Tests.ps1 — a suite failed to load; refusing to capture a partial baseline."
}
# (2) Observed coverage actually clears the target we're about to record, so the
#     freshly written baseline can't immediately fail CI.
$pct = [math]::Round($r.CodeCoverage.CoveragePercent, 1)
if ($pct -lt $CoveragePercentTarget) {
    throw "Observed coverage $pct% is below the target $CoveragePercentTarget% — refusing to write a baseline that would immediately fail CI. Raise coverage or pass a lower -CoveragePercentTarget."
}
$json = ConvertTo-CoverageBaselineJson `
    -CoveragePercentTarget $CoveragePercentTarget `
    -MinTotalTests $r.TotalCount

if ($DryRun) {
    Write-Host '--- coverage-baseline.json (dry run) ---'
    Write-Host $json
    Write-Host "(observed: $($r.TotalCount) tests across $($r.Containers.Count) files, coverage $pct%)"
    return
}

# Write LF + UTF-8 (no BOM) + a single trailing newline regardless of host OS —
# same byte-clean discipline as packages.lock.json (B4), so the committed
# baseline passes the repo's LF .editorconfig gate on every platform.
$json = ($json -replace "`r`n", "`n").TrimEnd("`n") + "`n"
[System.IO.File]::WriteAllText($baselinePath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $baselinePath  (test-case floor: $($r.TotalCount), target $CoveragePercentTarget%; observed coverage $pct% across $($r.Containers.Count) files — file count is auto-derived in CI)"
