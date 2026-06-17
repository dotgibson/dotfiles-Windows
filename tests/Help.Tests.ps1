# ============================================================================
#  tests/Help.Tests.ps1  -  dothelp catalog integrity + filtering.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # The help catalog + pure helpers now live in the Dotfiles module (B7 stage 2c);
    # import it for them (and for the renderer's Write-DotHost / Write-DotBanner). The
    # dothelp VERB stays host-side, so dot-source the fragment too to exercise it.
    $script:Module = Import-Module (Join-Path $RepoRoot 'powershell/Dotfiles/Dotfiles.psd1') -Force -DisableNameChecking -PassThru
    . (Join-Path $RepoRoot 'powershell/core/55-help.ps1')
}
AfterAll { if ($script:Module) { Remove-Module $script:Module -Force -ErrorAction SilentlyContinue } }

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
    It 'puts the description in field 2 and a real group in field 3 (picker preview contract)' {
        # The fzf picker (U9) shows command in the list and "[{3}] {2}" — group +
        # description — in the preview, so field order is a contract worth locking.
        $groups = @((Get-DotfilesHelpData).Keys)
        $parts = (Get-DotHelpFlatLines | Where-Object { ($_ -split "`t")[0] -eq 'lg' } | Select-Object -First 1) -split "`t"
        $parts[1] | Should -Not -BeNullOrEmpty   # description
        $groups   | Should -Contain $parts[2]    # group is a real catalog group
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

Describe 'Get-DotHelpPrimaryVerb' {
    It 'takes the first verb of a multi-verb cell' { Get-DotHelpPrimaryVerb 'g / gs / gl' | Should -Be 'g' }
    It 'skips a placeholder argument'              { Get-DotHelpPrimaryVerb 'mkbak <f>' | Should -Be 'mkbak' }
    It 'returns empty for an empty cell'           { Get-DotHelpPrimaryVerb '' | Should -Be '' }
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
