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
    It 'emits one "<display>`t<command>" line per entry' {
        $lines = Get-DotHelpFlatLines
        $lines.Count | Should -BeGreaterThan 10
        foreach ($l in $lines) { ($l -split "`t").Count | Should -Be 2 }
    }
    It 'puts the bare command in the last field for clean extraction on pick' {
        # The picker takes ($picked -split "`t")[-1], so padding/columns in the
        # display never leak onto the prompt.
        $cmds = Get-DotHelpFlatLines | ForEach-Object { ($_ -split "`t")[-1] }
        $cmds | Should -Contain 'lg'
    }
    It 'shows command, description and [group] together in the display column' {
        $line = Get-DotHelpFlatLines | Where-Object { ($_ -split "`t")[-1] -eq 'lg' } | Select-Object -First 1
        $disp = ($line -split "`t")[0]
        $disp | Should -Match 'lg'
        $disp | Should -Match 'lazygit'    # description
        $disp | Should -Match '\[Git\]'    # group tag
    }
    It 'renders cmd.exe metacharacters (& < >) literally, never shell-parsed' {
        # The reason the picker doesn't use an fzf --preview shell: these would be
        # a command separator / redirection under cmd.exe.
        $lines = Get-DotHelpFlatLines
        ($lines | Where-Object { $_ -match '\[Listing & files\]' }) | Should -Not -BeNullOrEmpty
        ($lines | Where-Object { ($_ -split "`t")[-1] -eq 'mkbak <f>' }) | Should -Not -BeNullOrEmpty
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
