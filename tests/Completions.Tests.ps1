# ============================================================================
#  tests/Completions.Tests.ps1  -  argument-completer registration + helper.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # 55-help defines Get-DotfilesHelpData/Get-DotHelpFilters/dothelp that the
    # dothelp completer leans on; load it before registering completers.
    . (Join-Path $RepoRoot 'powershell/core/55-help.ps1')
    # Stub the remaining target commands so completion resolves against real names.
    function global:mux       { param([string]$Session = 'main') }
    function global:cdwsl     { param([string]$Distro = 'kali-linux') }
    function global:maint-log { param($Arg = 50) }
    . (Join-Path $RepoRoot 'powershell/core/50-completions.ps1')
}
AfterAll {
    Remove-Item Function:\mux, Function:\cdwsl, Function:\maint-log -ErrorAction SilentlyContinue
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
}
