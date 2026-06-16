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

Describe 'Test-DotGum' {
    It 'is true when gum is present, colour on, interactive, and not opted out' {
        Test-DotGum -NoGum '' -HasGum $true -Color $true -Interactive $true | Should -BeTrue
    }
    It 'is false when DOTFILES_NO_GUM=1 (the escape hatch wins over everything)' {
        Test-DotGum -NoGum '1' -HasGum $true -Color $true -Interactive $true | Should -BeFalse
    }
    It 'is false when gum is not on PATH' {
        Test-DotGum -NoGum '' -HasGum $false -Color $true -Interactive $true | Should -BeFalse
    }
    It 'is false under NO_COLOR / TERM=dumb (colour off)' {
        Test-DotGum -NoGum '' -HasGum $true -Color $false -Interactive $true | Should -BeFalse
    }
    It 'is false when stdin is redirected / non-interactive' {
        Test-DotGum -NoGum '' -HasGum $true -Color $true -Interactive $false | Should -BeFalse
    }
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

Describe 'Get-DotConfirmAnswer' {
    It 'treats an empty answer as the default (yes)' { Get-DotConfirmAnswer '' $true  | Should -Be 'yes' }
    It 'treats an empty answer as the default (no)'  { Get-DotConfirmAnswer '' $false | Should -Be 'no' }
    It 'accepts y / yes (any case/space)'            { Get-DotConfirmAnswer '  YES ' | Should -Be 'yes' }
    It 'accepts n / no'                              { Get-DotConfirmAnswer 'n' | Should -Be 'no' }
    It 'flags a typo as invalid (not a silent no)'   { Get-DotConfirmAnswer 'yse' | Should -Be 'invalid' }
}

Describe 'Get-DotStringSha256' {
    It 'matches the known SHA-256 of "abc"' {
        Get-DotStringSha256 'abc' | Should -Be 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }
    It 'hashes the empty string to the well-known digest' {
        Get-DotStringSha256 '' | Should -Be 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    }
    It 'is lowercase hex of length 64' {
        Get-DotStringSha256 'dotfiles' | Should -Match '^[0-9a-f]{64}$'
    }
}

Describe 'Get-DotSpinnerFrame' {
    It 'cycles through the unicode frames' {
        Get-DotSpinnerFrame -Tick 0  -Unicode $true | Should -Be '⠋'
        Get-DotSpinnerFrame -Tick 10 -Unicode $true | Should -Be '⠋'   # wraps (10 frames)
    }
    It 'uses an ASCII spinner when not unicode' {
        Get-DotSpinnerFrame -Tick 0 -Unicode $false | Should -Be '|'
        Get-DotSpinnerFrame -Tick 1 -Unicode $false | Should -Be '/'
    }
    It 'handles a negative tick without erroring' {
        { Get-DotSpinnerFrame -Tick -3 -Unicode $true } | Should -Not -Throw
    }
}

Describe 'Invoke-DotSpinner' {
    It 'runs the script inline and returns its output when not animating (NO_COLOR)' {
        $prev = $env:NO_COLOR
        try { $env:NO_COLOR = '1'; Invoke-DotSpinner -Label 'x' -Script { 21 * 2 } | Should -Be 42 }
        finally { $env:NO_COLOR = $prev }
    }
    It 'passes ArgumentList through inline' {
        $prev = $env:NO_COLOR
        try { $env:NO_COLOR = '1'; Invoke-DotSpinner -Label 'x' -ArgumentList @(3, 4) -Script { param($a, $b) $a + $b } | Should -Be 7 }
        finally { $env:NO_COLOR = $prev }
    }
}

Describe 'Test-DotEmailish' {
    It 'accepts a plausible address'      { Test-DotEmailish 'me@example.com' | Should -BeTrue }
    It 'accepts a sub-domain address'     { Test-DotEmailish 'a.b@mail.corp.io' | Should -BeTrue }
    It 'rejects a bare local part'        { Test-DotEmailish 'me@' | Should -BeFalse }
    It 'rejects a missing domain dot'     { Test-DotEmailish 'me@host' | Should -BeFalse }
    It 'rejects a name with no @'         { Test-DotEmailish 'Jane Doe' | Should -BeFalse }
    It 'rejects whitespace/empty'         { Test-DotEmailish '   ' | Should -BeFalse }
}

Describe 'Write-DotBanner' {
    It 'renders a plain == Title == under NO_COLOR' {
        $prev = $env:NO_COLOR
        try { $env:NO_COLOR = '1'; (Write-DotBanner 'Doctor' 6>&1 | Out-String).Trim() | Should -Be '== Doctor ==' }
        finally { $env:NO_COLOR = $prev }
    }
    It 'includes the subtitle under NO_COLOR' {
        $prev = $env:NO_COLOR
        try { $env:NO_COLOR = '1'; (Write-DotBanner 'A' -Subtitle 'B' 6>&1 | Out-String).Trim() | Should -Be '== A :: B ==' }
        finally { $env:NO_COLOR = $prev }
    }
    It 'does not throw with colour on' { { Write-DotBanner 'X' -Subtitle 'Y' 6>$null } | Should -Not -Throw }
}

Describe 'Write-DotRule' {
    It 'prefixes the title and draws a rule' {
        (Write-DotRule -Title 'Summary' -Width 5 6>&1 | Out-String) | Should -Match '-- Summary'
    }
    It 'uses ASCII dashes under DOTFILES_ASCII=1' {
        $prev = $env:DOTFILES_ASCII
        try { $env:DOTFILES_ASCII = '1'; (Write-DotRule -Width 4 6>&1 | Out-String).Trim() | Should -Be '----' }
        finally { $env:DOTFILES_ASCII = $prev }
    }
}

Describe 'Read-DotConfirm' {
    # Force the plain Read-Host path so these tests are deterministic even when the
    # dev box has gum installed and an interactive console (Test-DotGum would
    # otherwise route to `gum confirm` and bypass the mocked Read-Host).
    BeforeAll { $script:prevNoGum = $env:DOTFILES_NO_GUM; $env:DOTFILES_NO_GUM = '1' }
    AfterAll  { $env:DOTFILES_NO_GUM = $script:prevNoGum }

    It 'returns true when the user answers yes' {
        Mock Read-Host { 'y' }
        Read-DotConfirm 'go?' | Should -BeTrue
    }
    It 'returns false when the user answers no' {
        Mock Read-Host { 'n' }
        Read-DotConfirm 'go?' | Should -BeFalse
    }
    It 're-asks on an invalid answer, then honours the next valid one' {
        $script:calls = 0
        Mock Read-Host { $script:calls++; if ($script:calls -eq 1) { 'huh' } else { 'n' } }
        Read-DotConfirm 'go?' | Should -BeFalse
        Should -Invoke Read-Host -Times 2
    }
    It 'takes the default when there is no interactive host (Read-Host throws)' {
        Mock Read-Host { throw 'no host' }
        Read-DotConfirm 'go?' -DefaultYes $true | Should -BeTrue
        Read-DotConfirm 'go?' -DefaultYes $false | Should -BeFalse
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
