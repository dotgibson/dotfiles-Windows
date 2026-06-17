# ============================================================================
#  tests/CoverageGate.ps1  -  pure helpers for the CI coverage/anti-deletion
#  gate (B5).
#
#  The CI test step gates on three things: the coverage % the pure-helper surface
#  must hit, the number of test FILES that ran, and a FLOOR on how many test
#  cases ran (an anti-deletion tripwire — a dropped chunk of `It`s should fail the
#  build, not silently shrink the suite). These used to be hand-edited literals in
#  ci.yml, which drifted (minFiles sat at 13 while the suite grew past 17).
#
#  They are split by what each number actually IS:
#    • test-FILE count — NOT stored anywhere. The filesystem is the source of
#      truth, so CI counts tests/**/*.Tests.ps1 and asserts Pester discovered
#      EXACTLY that many. A suite that fails to load, or is removed/renamed, trips
#      it with zero maintenance (issue #29).
#    • coverage % target + test-case FLOOR — generated into a versioned,
#      checked-in baseline (coverage-baseline.json) refreshed by
#      Update-CoverageBaseline.ps1, the same "generate on a real run, commit the
#      artifact, gate against it" model B4 uses for packages.lock.json. The
#      case count is a FLOOR (two -ForEach blocks expand the real total past it),
#      so an exact match would be fragile; the coverage % is a deliberate bar.
#
#  Everything here is PURE (JSON / numbers in, object out — no Pester calls, no
#  disk writes, no globbing), so it is unit-tested offline in
#  tests/CoverageGate.Tests.ps1. Dot-sourced by Update-CoverageBaseline.ps1 (the
#  generator) and by ci.yml (the consumer); side-effect-free on load.
# ============================================================================

# --- Read-CoverageBaseline ----------------------------------------------------
# Parse coverage-baseline.json text into a validated
# { CoveragePercentTarget; MinTotalTests } object.
#
# STRICT by design (the opposite of Read-PackageLock's tolerant degrade): this
# is a CI gate, so a missing / blank / malformed / incomplete baseline must FAIL
# LOUDLY rather than coerce to zero — a zero floor would silently disable the
# anti-deletion tripwire and let the suite rot unnoticed. Hence we throw with a
# clear message instead of returning defaults.
function Read-CoverageBaseline {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw 'coverage baseline is empty — run tests/Update-CoverageBaseline.ps1 to generate it.'
    }
    try { $o = $Json | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "coverage baseline is not valid JSON: $($_.Exception.Message)" }

    foreach ($field in 'coveragePercentTarget', 'minTotalTests') {
        if ($null -eq $o.$field) { throw "coverage baseline is missing required field '$field'." }
    }

    $target = [double]$o.coveragePercentTarget
    $total  = [int]$o.minTotalTests
    if ($target -lt 0 -or $target -gt 100) { throw "coverage baseline coveragePercentTarget '$target' is out of range (0-100)." }
    if ($total -lt 1) { throw "coverage baseline minTotalTests '$total' must be >= 1." }

    [pscustomobject]@{
        CoveragePercentTarget = $target
        MinTotalTests         = $total
    }
}

# --- Get-CoverageGateResult ---------------------------------------------------
# Pure gate decision: compare an actual Pester run against the baseline (coverage
# bar + test-case floor) AND against the filesystem's test-file count (exact
# match), returning { Passed; Failures = @(message...) }. Collects ALL violations
# so one CI run reports every problem, not just the first. The caller renders.
#
# ExpectedFileCount is the tests/**/*.Tests.ps1 glob count — passed in (not
# globbed here) to keep this function pure and offline-testable. CI supplies it.
function Get-CoverageGateResult {
    param(
        [Parameter(Mandatory)][double]$CoveragePercent,
        [Parameter(Mandatory)][int]$TotalCount,
        [Parameter(Mandatory)][int]$FileCount,
        [Parameter(Mandatory)][int]$ExpectedFileCount,
        [Parameter(Mandatory)][psobject]$Baseline,
        [int]$FailedCount = 0
    )
    $failures = [System.Collections.Generic.List[string]]::new()
    $pct = [math]::Round($CoveragePercent, 1)

    if ($FailedCount -gt 0) {
        $failures.Add("$FailedCount test(s) failed.")
    }
    if ($CoveragePercent -lt $Baseline.CoveragePercentTarget) {
        $failures.Add("Coverage $pct% is below the $($Baseline.CoveragePercentTarget)% target for the pure-helper surface.")
    }
    if ($FileCount -ne $ExpectedFileCount) {
        $failures.Add("Pester ran $FileCount test file(s) but tests/ has $ExpectedFileCount *.Tests.ps1 — a suite failed to load, or was removed/renamed.")
    }
    if ($TotalCount -lt $Baseline.MinTotalTests) {
        $failures.Add("Only $TotalCount tests discovered (floor $($Baseline.MinTotalTests)) — were tests removed?")
    }

    [pscustomobject]@{
        Passed   = ($failures.Count -eq 0)
        Failures = $failures.ToArray()
    }
}

# --- ConvertTo-CoverageBaselineJson -------------------------------------------
# Render a baseline object back to the canonical, byte-stable JSON text the
# generator commits. Kept pure (no disk write) so the generator can dry-run it
# and the tests can assert its shape. The writer is responsible for LF/UTF-8.
function ConvertTo-CoverageBaselineJson {
    param(
        [Parameter(Mandatory)][double]$CoveragePercentTarget,
        [Parameter(Mandatory)][int]$MinTotalTests,
        [string]$GeneratedAt = ([DateTimeOffset]::Now.ToString('o'))
    )
    [ordered]@{
        _comment              = 'Generated by tests/Update-CoverageBaseline.ps1 - CI coverage target + test-case floor (B5). The test-FILE count is auto-derived from the tests glob, not stored here. Do not hand-edit; re-run the generator after intentionally removing tests.'
        generatedAt           = $GeneratedAt
        coveragePercentTarget = $CoveragePercentTarget
        minTotalTests         = $MinTotalTests
    } | ConvertTo-Json
}
