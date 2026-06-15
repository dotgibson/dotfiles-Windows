# ============================================================================
#  tests/Help.Tests.ps1  -  dothelp catalog integrity + filtering.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $RepoRoot 'powershell/core/55-help.ps1')
}

Describe 'Get-DotfilesHelpData' {
    It 'returns an ordered set of non-trivial groups' {
        $d = Get-DotfilesHelpData
        $d.Keys.Count | Should -BeGreaterThan 7
    }
    It 'every row has a non-empty Command and Desc' {
        $d = Get-DotfilesHelpData
        foreach ($g in $d.Keys) {
            foreach ($r in $d[$g]) {
                $r.Command | Should -Not -BeNullOrEmpty
                $r.Desc    | Should -Not -BeNullOrEmpty
            }
        }
    }
    It 'documents the headline verbs' {
        $all = (Get-DotfilesHelpData).Values | ForEach-Object { $_ } | ForEach-Object Command
        ($all -join ' ') | Should -Match '\bup\b'
        ($all -join ' ') | Should -Match 'mux'
        ($all -join ' ') | Should -Match 'dotfiles-doctor'
    }
}

Describe 'dothelp' {
    It 'runs without error for the full index' {
        { dothelp } | Should -Not -Throw
    }
    It 'runs without error for a filter that matches nothing' {
        { dothelp 'zzz-no-such-command' } | Should -Not -Throw
    }
}
