# ============================================================================
#  tests/Completions.Tests.ps1  -  argument-completer registration + helper.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # The dothelp completer leans on Get-DotHelpFilters, which now lives in the
    # Dotfiles module (B7 stage 2c) — import it so the completer resolves it. Still
    # dot-source 55-help for the dothelp VERB the completer is registered against.
    $script:Module = Import-Module (Join-Path $RepoRoot 'powershell/Dotfiles/Dotfiles.psd1') -Force -DisableNameChecking -PassThru
    . (Join-Path $RepoRoot 'powershell/core/55-help.ps1')
    . (Join-Path $PSScriptRoot '_TestHelpers.ps1')   # New-DotTestTempDir
    # Stub the remaining target commands so completion resolves against real names.
    function global:mux       { param([string]$Session = 'main') }
    function global:cdwsl     { param([string]$Distro = 'kali-linux') }
    function global:maint-log { param($Arg = 50) }
    function global:sci       { param([Parameter(ValueFromRemainingArguments)][string[]]$App) }
    function global:wgi       { param($id) }
    # The managed-package completers read the repo manifests via $global:DOTFILES.
    $global:DOTFILES = $RepoRoot
    . (Join-Path $RepoRoot 'powershell/core/50-completions.ps1')
}
AfterAll {
    Remove-Item Function:\mux, Function:\cdwsl, Function:\maint-log, Function:\sci, Function:\wgi -ErrorAction SilentlyContinue
    if ($script:Module) { Remove-Module $script:Module -Force -ErrorAction SilentlyContinue }
}

Describe 'New-DotCompletions' {
    It 'prefix-filters, de-duplicates, and sorts' {
        $r = New-DotCompletions -Values @('main', 'scan', 'main', 'dev') -Word 'ma'
        $r.CompletionText | Should -Be @('main')
    }
    It 'returns nothing for a non-matching prefix' {
        (New-DotCompletions -Values @('main', 'dev') -Word 'zzz') | Should -BeNullOrEmpty
    }
}

Describe 'argument completers are registered' {
    It 'offers -f for maint-log' {
        $line = 'maint-log '
        $tab = TabExpansion2 $line $line.Length
        $tab.CompletionMatches.CompletionText | Should -Contain '-f'
    }
    It 'completes dothelp filters from the catalog' {
        $line = 'dothelp g'
        $tab = TabExpansion2 $line $line.Length
        $tab.CompletionMatches.CompletionText | Should -Contain 'git'
    }
    It 'completes sci from the managed scoop manifest' {
        $line = 'sci star'
        $tab = TabExpansion2 $line $line.Length
        $tab.CompletionMatches.CompletionText | Should -Contain 'starship'
    }
    It 'completes wgi from the managed winget manifest' {
        $line = 'wgi Microsoft.Win'
        $tab = TabExpansion2 $line $line.Length
        $tab.CompletionMatches.CompletionText | Should -Contain 'Microsoft.WindowsTerminal'
    }
    It 'normalizes pinned { id, version } winget entries to id strings' {
        # Guards the B2 pinned-entry shape: the completer must never emit a
        # PSCustomObject. Point $global:DOTFILES at a temp manifest with both forms.
        $tmp = New-DotTestTempDir -Prefix 'wgnorm'
        New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'packages') | Out-Null
        try {
            @{ packages = @('Git.Git', @{ id = 'Mozilla.Firefox'; version = '120.0' }) } |
                ConvertTo-Json -Depth 5 | Set-Content (Join-Path $tmp 'packages\winget.json')
            $prev = $global:DOTFILES
            try {
                $global:DOTFILES = $tmp
                $ids = Get-DotManagedWingetIds
                $ids | Should -Contain 'Mozilla.Firefox'
                @($ids | Where-Object { $_ -isnot [string] }) | Should -BeNullOrEmpty
            } finally { $global:DOTFILES = $prev }
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
