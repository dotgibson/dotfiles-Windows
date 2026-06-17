# ============================================================================
#  tests/CoverageGate.Tests.ps1  -  pure CI coverage-gate helpers (B5).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $RepoRoot 'tests/CoverageGate.ps1')
    # A representative baseline for the gate tests.
    $script:BL = [pscustomobject]@{ CoveragePercentTarget = 85; MinTotalTests = 160 }
}

Describe 'Read-CoverageBaseline' {
    It 'parses a well-formed baseline into typed fields' {
        $b = Read-CoverageBaseline '{ "coveragePercentTarget": 85, "minTotalTests": 160 }'
        $b.CoveragePercentTarget | Should -Be 85
        $b.MinTotalTests | Should -Be 160
    }
    It 'does NOT expose a stored file floor (auto-derived in CI)' {
        $b = Read-CoverageBaseline '{ "coveragePercentTarget": 85, "minTotalTests": 160 }'
        $b.PSObject.Properties.Name | Should -Not -Contain 'MinTestFiles'
    }
    It 'parses the checked-in baseline file' {
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests/coverage-baseline.json'
        $b = Read-CoverageBaseline (Get-Content $path -Raw)
        $b.MinTotalTests | Should -BeGreaterThan 0
        $b.CoveragePercentTarget | Should -BeGreaterThan 0
    }
    It 'throws (does NOT degrade to a zero floor) on blank input' {
        { Read-CoverageBaseline '' } | Should -Throw '*empty*'
    }
    It 'throws on malformed JSON' {
        { Read-CoverageBaseline 'not json {{' } | Should -Throw '*not valid JSON*'
    }
    It 'throws when a required field is missing' {
        { Read-CoverageBaseline '{ "minTotalTests": 160 }' } | Should -Throw "*coveragePercentTarget*"
    }
    It 'throws on an out-of-range coverage target' {
        { Read-CoverageBaseline '{ "coveragePercentTarget": 150, "minTotalTests": 160 }' } | Should -Throw '*out of range*'
    }
    It 'throws on a non-positive floor' {
        { Read-CoverageBaseline '{ "coveragePercentTarget": 85, "minTotalTests": 0 }' } | Should -Throw '*minTotalTests*'
    }
}

Describe 'Get-CoverageGateResult' {
    It 'passes when every metric meets the baseline and files match exactly' {
        $r = Get-CoverageGateResult -CoveragePercent 92.3 -TotalCount 200 -FileCount 18 -ExpectedFileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeTrue
        $r.Failures | Should -BeNullOrEmpty
    }
    It 'passes exactly at the coverage/total thresholds (>=, not >)' {
        $r = Get-CoverageGateResult -CoveragePercent 85 -TotalCount 160 -FileCount 18 -ExpectedFileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeTrue
    }
    It 'fails and names the shortfall when coverage is below target' {
        $r = Get-CoverageGateResult -CoveragePercent 80.4 -TotalCount 200 -FileCount 18 -ExpectedFileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*80.4% is below the 85*'
    }
    It 'compares the DISPLAYED (rounded) coverage, so message and decision agree' {
        # 84.96 rounds to 85.0 — it must PASS an 85 target, never print the
        # self-contradictory "85.0% is below 85%".
        (Get-CoverageGateResult -CoveragePercent 84.96 -TotalCount 200 -FileCount 18 -ExpectedFileCount 18 -Baseline $script:BL).Passed | Should -BeTrue
        # 84.94 rounds to 84.9 — fails, and the message shows that same value.
        $r = Get-CoverageGateResult -CoveragePercent 84.94 -TotalCount 200 -FileCount 18 -ExpectedFileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*84.9% is below the 85*'
    }
    It 'fails when Pester ran FEWER files than the glob (a suite failed to load)' {
        $r = Get-CoverageGateResult -CoveragePercent 92 -TotalCount 200 -FileCount 17 -ExpectedFileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*ran 17 test file(s) but tests/ has 18*'
    }
    It 'fails when the file counts differ in EITHER direction (exact match)' {
        $r = Get-CoverageGateResult -CoveragePercent 92 -TotalCount 200 -FileCount 19 -ExpectedFileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*ran 19 test file(s) but tests/ has 18*'
    }
    It 'fails when test cases dropped below the floor' {
        $r = Get-CoverageGateResult -CoveragePercent 92 -TotalCount 159 -FileCount 18 -ExpectedFileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*159 tests discovered (floor 160)*'
    }
    It 'surfaces a hard test failure even when the other gates pass' {
        $r = Get-CoverageGateResult -CoveragePercent 92 -TotalCount 200 -FileCount 18 -ExpectedFileCount 18 -Baseline $script:BL -FailedCount 3
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*3 test(s) failed*'
    }
    It 'collects ALL violations in one pass (not just the first)' {
        $r = Get-CoverageGateResult -CoveragePercent 50 -TotalCount 10 -FileCount 2 -ExpectedFileCount 18 -Baseline $script:BL -FailedCount 1
        $r.Passed | Should -BeFalse
        $r.Failures | Should -HaveCount 4
    }
}

Describe 'ConvertTo-CoverageBaselineJson' {
    It 'round-trips through Read-CoverageBaseline' {
        $json = ConvertTo-CoverageBaselineJson -CoveragePercentTarget 90 -MinTotalTests 175
        $b = Read-CoverageBaseline $json
        $b.CoveragePercentTarget | Should -Be 90
        $b.MinTotalTests | Should -Be 175
    }
    It 'does not emit a stored file count' {
        (ConvertTo-CoverageBaselineJson -CoveragePercentTarget 85 -MinTotalTests 160) |
            Should -Not -BeLike '*minTestFiles*'
    }
    It 'carries the do-not-hand-edit comment' {
        (ConvertTo-CoverageBaselineJson -CoveragePercentTarget 85 -MinTotalTests 160) |
            Should -BeLike '*re-run the generator*'
    }
}
