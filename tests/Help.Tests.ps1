# ============================================================================
#  tests/Help.Tests.ps1  -  dothelp catalog integrity + filtering.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # Load the shared lib first (profile load order) so dothelp's colour helper
    # (Write-DotHost / Test-DotColor) is available when it renders.
    . (Join-Path $RepoRoot 'powershell/core/05-lib.ps1')
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

Describe 'Get-DotHelpFlatLines' {
    It 'emits one tab-delimited command/desc/group line per entry' {
        $lines = Get-DotHelpFlatLines
        $lines.Count | Should -BeGreaterThan 10
        foreach ($l in $lines) { ($l -split "`t").Count | Should -Be 3 }
    }
    It 'includes a known command in the first field' {
        $cmds = Get-DotHelpFlatLines | ForEach-Object { ($_ -split "`t")[0] }
        $cmds | Should -Contain 'lg'
    }
}

Describe 'Get-DotHelpFilters' {
    It 'includes group names and individual command verbs' {
        $f = Get-DotHelpFilters
        $f | Should -Contain 'Git'
        $f | Should -Contain 'git'
        $f | Should -Contain 'lg'
    }
    It 'excludes placeholder tokens like <dir> / [filter]' {
        $f = Get-DotHelpFilters
        ($f | Where-Object { $_ -match '^[<\[]' }) | Should -BeNullOrEmpty
    }
}

Describe 'Get-DotLevenshtein' {
    It 'is zero for identical strings' { Get-DotLevenshtein 'reload' 'reload' | Should -Be 0 }
    It 'counts a single deletion'      { Get-DotLevenshtein 'reload' 'relod' | Should -Be 1 }
    It 'handles an empty operand'      { Get-DotLevenshtein '' 'abc' | Should -Be 3 }
}

Describe 'Get-DotDidYouMean' {
    BeforeAll { $script:Cands = Get-DotHelpFilters }
    It 'suggests the real verb for a near typo' {
        Get-DotDidYouMean -Name 'dohelp' -Candidates $script:Cands | Should -Contain 'dothelp'
    }
    It 'resolves a dropped-letter typo' {
        Get-DotDidYouMean -Name 'relod' -Candidates $script:Cands | Should -Contain 'reload'
    }
    It 'stays silent for a wholly unrelated token' {
        Get-DotDidYouMean -Name 'xyzzy' -Candidates $script:Cands | Should -BeNullOrEmpty
    }
    It 'does not suggest a short flag/alias for a long typo' {
        # a long mistype that happens to contain "-n" must not surface "-n"
        Get-DotDidYouMean -Name 'relodd-nonexistent' -Candidates $script:Cands | Should -Not -Contain '-n'
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
