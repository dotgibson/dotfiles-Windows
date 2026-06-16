# ============================================================================
#  tests/Lib.Tests.ps1  -  behavioral tests for the pure helpers in
#  powershell/core/05-lib.ps1. Dot-sourced in isolation (no side effects).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $RepoRoot 'powershell/core/05-lib.ps1')
}

Describe 'Test-SensitiveHistoryLine' {
    Context 'must KEEP (not sensitive)' {
        It 'keeps the bare pwd command' { Test-SensitiveHistoryLine 'pwd' | Should -BeFalse }
        It 'keeps cd then pwd'          { Test-SensitiveHistoryLine 'cd C:\src; pwd' | Should -BeFalse }
        It 'keeps a "first pass" commit' { Test-SensitiveHistoryLine 'gcm "first pass at the parser"' | Should -BeFalse }
        It 'keeps words containing pass' { Test-SensitiveHistoryLine 'Compress-Archive .\a .\b' | Should -BeFalse }
        It 'keeps a normal ls'          { Test-SensitiveHistoryLine 'll -a' | Should -BeFalse }
        It 'keeps empty / whitespace'   { Test-SensitiveHistoryLine '   ' | Should -BeFalse }
    }
    Context 'must DROP (sensitive)' {
        It 'drops op read'              { Test-SensitiveHistoryLine 'op read op://Personal/AWS/key' | Should -BeTrue }
        It 'drops op item get'          { Test-SensitiveHistoryLine 'op item get GitHub --otp' | Should -BeTrue }
        It 'drops a PASSWORD= assign'   { Test-SensitiveHistoryLine '$env:PASSWORD="hunter2"' | Should -BeTrue }
        It 'drops a token keyword'      { Test-SensitiveHistoryLine 'export GH_TOKEN=ghp_xxx' | Should -BeTrue }
        It 'drops an api-key keyword'   { Test-SensitiveHistoryLine 'setx OPENAI_API_KEY sk-123' | Should -BeTrue }
        It 'drops a --api-key flag'     { Test-SensitiveHistoryLine 'tool --api-key=sk-1' | Should -BeTrue }
        It 'drops a --api_key flag'     { Test-SensitiveHistoryLine 'tool --api_key sk-1' | Should -BeTrue }
        It 'drops an x-api-key header'  { Test-SensitiveHistoryLine 'curl -H "x-api-key: sk-1"' | Should -BeTrue }
        It 'drops a --password flag'    { Test-SensitiveHistoryLine 'mysql --password=s3cr3t -u root' | Should -BeTrue }
        It 'drops a private-key mention'{ Test-SensitiveHistoryLine 'cat ~/.ssh/id_ed25519 # private key' | Should -BeTrue }
    }
}

Describe 'Test-DotColor' {
    It 'enables colour by default'        { Test-DotColor -NoColor '' -Term 'xterm' | Should -BeTrue }
    It 'disables colour when NO_COLOR set' { Test-DotColor -NoColor '1' -Term 'xterm' | Should -BeFalse }
    It 'disables colour for TERM=dumb'    { Test-DotColor -NoColor '' -Term 'dumb' | Should -BeFalse }
}

Describe 'Test-DotUnicode' {
    It 'is unicode by default'             { Test-DotUnicode -Ascii '' | Should -BeTrue }
    It 'falls back to ASCII when forced'   { Test-DotUnicode -Ascii '1' | Should -BeFalse }
}

Describe 'Get-DotGlyph' {
    It 'returns the unicode glyph by default'   { Get-DotGlyph -Name fail -Unicode $true | Should -Be '✗' }
    It 'returns an ASCII fallback when asked'   { Get-DotGlyph -Name fail -Unicode $false | Should -Be 'x' }
    It 'maps the arrow both ways' {
        Get-DotGlyph arrow -Unicode $true  | Should -Be '→'
        Get-DotGlyph arrow -Unicode $false | Should -Be '->'
    }
    It 'maps the package glyph both ways' {
        Get-DotGlyph pkg -Unicode $true  | Should -Be '⇧'
        Get-DotGlyph pkg -Unicode $false | Should -Be '^'
    }
    It 'rejects an unknown glyph name' { { Get-DotGlyph -Name nope } | Should -Throw }
}

Describe 'Write-DotErr' {
    It 'composes message and hint with -PassThru' {
        $out = Write-DotErr -Message 'boom' -Hint 'do this' -PassThru 6>$null
        $out | Should -Match '✗ boom'
        $out | Should -Match '→ do this'
    }
    It 'omits the hint line when none is given' {
        (Write-DotErr -Message 'only' -PassThru 6>$null) | Should -Be '✗ only'
    }
    It 'uses ASCII glyphs under DOTFILES_ASCII=1' {
        $prev = $env:DOTFILES_ASCII
        try {
            $env:DOTFILES_ASCII = '1'
            (Write-DotErr -Message 'only' -PassThru 6>$null) | Should -Be 'x only'
        } finally { $env:DOTFILES_ASCII = $prev }
    }
}

Describe 'Write-DotWarn' {
    It 'composes a warning with the bang glyph and hint' {
        $out = Write-DotWarn -Message 'heads up' -Hint 'try this' -PassThru 6>$null
        $out | Should -Match '! heads up'
        $out | Should -Match '→ try this'
    }
    It 'omits the hint line when none is given' {
        (Write-DotWarn -Message 'bare' -PassThru 6>$null) | Should -Be '! bare'
    }
}

Describe 'Get-DotfilesLinkPlan' {
    It 'derives every link from the injected roots' {
        $plan = Get-DotfilesLinkPlan -RepoRoot 'R:\repo' -HomeDir 'H:\me' -LocalAppData 'L:\app' -Documents 'D:\docs'
        $links = $plan.Link
        $links | Should -Contain 'H:\me\.gitconfig'
        $links | Should -Contain 'L:\app\nvim'
        $links | Should -Contain 'D:\docs\PowerShell\Microsoft.PowerShell_profile.ps1'
    }
    It 'derives every target from the repo root' {
        $plan = Get-DotfilesLinkPlan -RepoRoot 'R:\repo' -HomeDir 'H:' -LocalAppData 'L:' -Documents 'D:'
        ($plan.Target -join ';') | Should -Match ([regex]::Escape('R:\repo\git\.gitconfig'))
        ($plan.Target -join ';') | Should -Match ([regex]::Escape('R:\repo\windows-terminal\settings.json'))
    }
    It 'covers the full family of configs (parity with the installer)' {
        $links = (Get-DotfilesLinkPlan -RepoRoot 'R:' -HomeDir 'H:' -LocalAppData 'L:' -Documents 'D:').Link -join ';'
        foreach ($needle in 'profile.ps1', 'nvim', '.gitconfig', '.gitignore_global', 'ssh\config',
                            'psmux.conf', 'psmux.reset.conf', 'psmux\scripts', 'settings.json') {
            $links | Should -Match ([regex]::Escape($needle))
        }
    }
    It 'flags only Windows Terminal as ParentMustExist' {
        $plan = Get-DotfilesLinkPlan -RepoRoot 'R:' -HomeDir 'H:' -LocalAppData 'L:' -Documents 'D:'
        @($plan | Where-Object ParentMustExist).Name | Should -Be 'Windows Terminal settings'
    }
}

Describe 'Write-DotOk' {
    It 'composes a success line with the ok glyph and hint' {
        $out = Write-DotOk -Message 'all set' -Hint 'next: reload' -PassThru 6>$null
        $out | Should -Match '✓ all set'
        $out | Should -Match '→ next: reload'
    }
    It 'omits the hint line when none is given' {
        (Write-DotOk -Message 'done' -PassThru 6>$null) | Should -Be '✓ done'
    }
    It 'uses an ASCII glyph under DOTFILES_ASCII=1' {
        $prev = $env:DOTFILES_ASCII
        try {
            $env:DOTFILES_ASCII = '1'
            (Write-DotOk -Message 'done' -PassThru 6>$null) | Should -Be 'OK done'
        } finally { $env:DOTFILES_ASCII = $prev }
    }
}
