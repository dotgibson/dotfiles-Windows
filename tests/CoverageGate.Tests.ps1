# ============================================================================
#  tests/CoverageGate.Tests.ps1  -  pure CI coverage-gate helpers (B5).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $RepoRoot 'tests/CoverageGate.ps1')
    # A representative baseline for the gate tests.
    $script:BL = [pscustomobject]@{ CoveragePercentTarget = 85; MinTestFiles = 13; MinTotalTests = 160 }
}

Describe 'Read-CoverageBaseline' {
    It 'parses a well-formed baseline into typed fields' {
        $b = Read-CoverageBaseline '{ "coveragePercentTarget": 85, "minTestFiles": 13, "minTotalTests": 160 }'
        $b.CoveragePercentTarget | Should -Be 85
        $b.MinTestFiles  | Should -Be 13
        $b.MinTotalTests | Should -Be 160
    }
    It 'parses the checked-in baseline file' {
        $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests/coverage-baseline.json'
        $b = Read-CoverageBaseline (Get-Content $path -Raw)
        $b.MinTestFiles  | Should -BeGreaterThan 0
        $b.MinTotalTests | Should -BeGreaterThan 0
        $b.CoveragePercentTarget | Should -BeGreaterThan 0
    }
    It 'throws (does NOT degrade to zero floors) on blank input' {
        { Read-CoverageBaseline '' } | Should -Throw '*empty*'
    }
    It 'throws on malformed JSON' {
        { Read-CoverageBaseline 'not json {{' } | Should -Throw '*not valid JSON*'
    }
    It 'throws when a required field is missing' {
        { Read-CoverageBaseline '{ "minTestFiles": 13, "minTotalTests": 160 }' } | Should -Throw "*coveragePercentTarget*"
    }
    It 'throws on an out-of-range coverage target' {
        { Read-CoverageBaseline '{ "coveragePercentTarget": 150, "minTestFiles": 13, "minTotalTests": 160 }' } | Should -Throw '*out of range*'
    }
    It 'throws on a non-positive floor' {
        { Read-CoverageBaseline '{ "coveragePercentTarget": 85, "minTestFiles": 0, "minTotalTests": 160 }' } | Should -Throw '*minTestFiles*'
    }
}

Describe 'Get-CoverageGateResult' {
    It 'passes when every metric meets the baseline' {
        $r = Get-CoverageGateResult -CoveragePercent 92.3 -TotalCount 200 -FileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeTrue
        $r.Failures | Should -BeNullOrEmpty
    }
    It 'passes exactly at the thresholds (>=, not >)' {
        $r = Get-CoverageGateResult -CoveragePercent 85 -TotalCount 160 -FileCount 13 -Baseline $script:BL
        $r.Passed | Should -BeTrue
    }
    It 'fails and names the shortfall when coverage is below target' {
        $r = Get-CoverageGateResult -CoveragePercent 80.4 -TotalCount 200 -FileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*80.4% is below the 85*'
    }
    It 'fails when a test file went missing' {
        $r = Get-CoverageGateResult -CoveragePercent 92 -TotalCount 200 -FileCount 12 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*test file(s) ran (floor 13)*'
    }
    It 'fails when test cases dropped below the floor' {
        $r = Get-CoverageGateResult -CoveragePercent 92 -TotalCount 159 -FileCount 18 -Baseline $script:BL
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*159 tests discovered (floor 160)*'
    }
    It 'surfaces a hard test failure even when the floors are met' {
        $r = Get-CoverageGateResult -CoveragePercent 92 -TotalCount 200 -FileCount 18 -Baseline $script:BL -FailedCount 3
        $r.Passed | Should -BeFalse
        ($r.Failures -join "`n") | Should -BeLike '*3 test(s) failed*'
    }
    It 'collects ALL violations in one pass (not just the first)' {
        $r = Get-CoverageGateResult -CoveragePercent 50 -TotalCount 10 -FileCount 2 -Baseline $script:BL -FailedCount 1
        $r.Passed | Should -BeFalse
        $r.Failures | Should -HaveCount 4
    }
}

Describe 'ConvertTo-CoverageBaselineJson' {
    It 'round-trips through Read-CoverageBaseline' {
        $json = ConvertTo-CoverageBaselineJson -CoveragePercentTarget 90 -MinTestFiles 14 -MinTotalTests 175
        $b = Read-CoverageBaseline $json
        $b.CoveragePercentTarget | Should -Be 90
        $b.MinTestFiles  | Should -Be 14
        $b.MinTotalTests | Should -Be 175
    }
    It 'carries the do-not-hand-edit comment' {
        (ConvertTo-CoverageBaselineJson -CoveragePercentTarget 85 -MinTestFiles 13 -MinTotalTests 160) |
            Should -BeLike '*re-run the generator*'
    }
}
