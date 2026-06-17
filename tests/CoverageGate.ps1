# ============================================================================
#  tests/CoverageGate.ps1  -  pure helpers for the CI coverage/anti-deletion
#  gate (B5).
#
#  The CI test step gates on three numbers: the coverage % the pure-helper
#  surface must hit, and the FLOORS for how many test files and test cases must
#  run (an anti-deletion tripwire — a dropped *.Tests.ps1 or a deleted chunk of
#  `It`s should fail the build, not silently shrink the suite). Those numbers
#  used to be hand-edited literals in ci.yml, which drifted and were easy to
#  forget. They now live in a generated, checked-in baseline (coverage-baseline
#  .json) refreshed by Update-CoverageBaseline.ps1 — the same "generate on a real
#  run, commit the artifact, gate against it" model B4 uses for packages.lock.json.
#
#  Everything here is PURE (JSON / numbers in, object out — no Pester calls, no
#  disk writes), so it is unit-tested offline in tests/CoverageGate.Tests.ps1.
#  Dot-sourced by Update-CoverageBaseline.ps1 (the generator) and by ci.yml (the
#  consumer); side-effect-free on load.
# ============================================================================

# --- Read-CoverageBaseline ----------------------------------------------------
# Parse coverage-baseline.json text into a validated
# { CoveragePercentTarget; MinTestFiles; MinTotalTests } object.
#
# STRICT by design (the opposite of Read-PackageLock's tolerant degrade): this
# is a CI gate, so a missing / blank / malformed / incomplete baseline must FAIL
# LOUDLY rather than coerce to zero — zero floors would silently disable the
# anti-deletion tripwire and let the suite rot unnoticed. Hence we throw with a
# clear message instead of returning defaults.
function Read-CoverageBaseline {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw 'coverage baseline is empty — run tests/Update-CoverageBaseline.ps1 to generate it.'
    }
    try { $o = $Json | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "coverage baseline is not valid JSON: $($_.Exception.Message)" }

    foreach ($field in 'coveragePercentTarget', 'minTestFiles', 'minTotalTests') {
        if ($null -eq $o.$field) { throw "coverage baseline is missing required field '$field'." }
    }

    $target = [double]$o.coveragePercentTarget
    $files  = [int]$o.minTestFiles
    $total  = [int]$o.minTotalTests
    if ($target -lt 0 -or $target -gt 100) { throw "coverage baseline coveragePercentTarget '$target' is out of range (0-100)." }
    if ($files -lt 1) { throw "coverage baseline minTestFiles '$files' must be >= 1." }
    if ($total -lt 1) { throw "coverage baseline minTotalTests '$total' must be >= 1." }

    [pscustomobject]@{
        CoveragePercentTarget = $target
        MinTestFiles          = $files
        MinTotalTests         = $total
    }
}

# --- Get-CoverageGateResult ---------------------------------------------------
# Pure gate decision: compare an actual Pester run (coverage %, test-case count,
# test-file count, failure count) against a baseline and return
# { Passed; Failures = @(message...) }. Collects ALL violations so one CI run
# reports every problem, not just the first. The caller renders/throws.
function Get-CoverageGateResult {
    param(
        [Parameter(Mandatory)][double]$CoveragePercent,
        [Parameter(Mandatory)][int]$TotalCount,
        [Parameter(Mandatory)][int]$FileCount,
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
    if ($FileCount -lt $Baseline.MinTestFiles) {
        $failures.Add("Only $FileCount test file(s) ran (floor $($Baseline.MinTestFiles)) — did a *.Tests.ps1 file get removed?")
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
        [Parameter(Mandatory)][int]$MinTestFiles,
        [Parameter(Mandatory)][int]$MinTotalTests,
        [string]$GeneratedAt = ([DateTimeOffset]::Now.ToString('o'))
    )
    [ordered]@{
        _comment              = 'Generated by tests/Update-CoverageBaseline.ps1 - CI coverage + anti-deletion floors (B5). Do not hand-edit; re-run the generator after intentionally adding/removing tests.'
        generatedAt           = $GeneratedAt
        coveragePercentTarget = $CoveragePercentTarget
        minTestFiles          = $MinTestFiles
        minTotalTests         = $MinTotalTests
    } | ConvertTo-Json
}
