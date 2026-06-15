# ============================================================================
#  tests/Doctor.Tests.ps1  -  dotfiles-doctor result model + aggregation.
#  (Host-specific probes are not exercised; the pure logic is.)
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # Load the shared lib first (profile load order) so the renderer's glyph/colour
    # helpers are present.
    . (Join-Path $RepoRoot 'powershell/core/05-lib.ps1')
    . (Join-Path $RepoRoot 'powershell/os/45-doctor.ps1')
}

Describe 'New-DoctorResult' {
    It 'builds a result with the expected shape' {
        $r = New-DoctorResult -Name 'thing' -Status 'ok' -Detail 'd' -Hint 'h'
        $r.Name | Should -Be 'thing'
        $r.Status | Should -Be 'ok'
    }
    It 'rejects an invalid status' {
        { New-DoctorResult -Name 'x' -Status 'bogus' } | Should -Throw
    }
}

Describe 'Get-DoctorSummary' {
    It 'counts ok/warn/fail correctly' {
        $s = Get-DoctorSummary @(
            (New-DoctorResult a ok), (New-DoctorResult b warn),
            (New-DoctorResult c fail), (New-DoctorResult d ok)
        )
        $s.Ok | Should -Be 2; $s.Warn | Should -Be 1; $s.Fail | Should -Be 1
    }
    It 'overall is fail if any fail' {
        (Get-DoctorSummary @((New-DoctorResult a ok), (New-DoctorResult b fail))).Overall | Should -Be 'fail'
    }
    It 'overall is warn if warns but no fails' {
        (Get-DoctorSummary @((New-DoctorResult a ok), (New-DoctorResult b warn))).Overall | Should -Be 'warn'
    }
    It 'overall is ok if all ok' {
        (Get-DoctorSummary @((New-DoctorResult a ok))).Overall | Should -Be 'ok'
    }
}
