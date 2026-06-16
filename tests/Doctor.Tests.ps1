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

Describe 'Get-FragmentHealthResult' {
    It 'warns when the profile never loaded (null)' {
        (Get-FragmentHealthResult $null).Status | Should -Be 'warn'
    }
    It 'is ok for an empty error list' {
        (Get-FragmentHealthResult @()).Status | Should -Be 'ok'
    }
    It 'fails and reports the count + first failure' {
        $res = Get-FragmentHealthResult @('core/10-tools.ps1: boom', 'os/40-maint.ps1: nope')
        $res.Status | Should -Be 'fail'
        $res.Detail | Should -Match '2 failed'
        $res.Detail | Should -Match '10-tools'
    }
}

Describe 'Get-DoctorFixPlan' {
    It 'is empty when everything is ok' {
        (Get-DoctorFixPlan @((New-DoctorResult 'Execution policy' 'ok'))) | Should -BeNullOrEmpty
    }
    It 'maps known failing checks to deduped actions' {
        $plan = Get-DoctorFixPlan @(
            (New-DoctorResult 'Execution policy' 'fail'),
            (New-DoctorResult 'Profile link' 'warn'),
            (New-DoctorResult 'link: .gitconfig' 'warn'),
            (New-DoctorResult 'Modules off OneDrive' 'warn'),
            (New-DoctorResult 'Core toolchain' 'warn')
        )
        $plan | Should -Contain 'execpolicy'
        $plan | Should -Contain 'rewire'
        $plan | Should -Contain 'localize-modules'
        $plan | Should -Contain 'install-packages'
        # 'Profile link' + 'link: .gitconfig' both collapse to a single rewire.
        ($plan | Where-Object { $_ -eq 'rewire' }).Count | Should -Be 1
    }
    It 'ignores checks it has no remedy for' {
        (Get-DoctorFixPlan @((New-DoctorResult 'git identity' 'warn'))) | Should -BeNullOrEmpty
    }
}

Describe 'Get-DotRepoVersionDetail' {
    It 'formats sha + date + dirty marker' {
        $d = Get-DotRepoVersionDetail -Sha 'abc1234' -IsDirty $true -When '2026-06-16'
        $d | Should -Match 'abc1234'
        $d | Should -Match '2026-06-16'
        $d | Should -Match '\[dirty\]'
    }
    It 'omits the dirty marker on a clean tree' {
        (Get-DotRepoVersionDetail -Sha 'abc1234' -IsDirty $false) | Should -Not -Match '\[dirty\]'
    }
    It 'reports unknown when there is no sha' {
        (Get-DotRepoVersionDetail -Sha '' -IsDirty $false) | Should -Match 'unknown'
    }
}

Describe 'Get-NvimVendorDetail' {
    It 'formats the short sha + commit date' {
        $d = Get-NvimVendorDetail -Sha 'abcdef1234567' -When '2026-06-16'
        $d | Should -Match 'core@abcdef1'
        $d | Should -Match '2026-06-16'
    }
    It 'omits the date when it is unknown' {
        (Get-NvimVendorDetail -Sha 'abcdef1' -When 'unknown') | Should -Not -Match '\('
    }
    It 'reports a missing ref when there is no sha' {
        (Get-NvimVendorDetail -Sha '' -When '') | Should -Match 'no vendor ref'
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
