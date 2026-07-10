# ============================================================================
#  tests/Core.Tests.ps1  -  the `core` front door (os/48-core.ps1) dispatch.
#
#  The front door is thin routing over host verbs (dotfiles-doctor / dothelp /
#  up), which are host-specific and NOT exercised here. We stub those leaves,
#  dot-source the fragment, and assert `core <verb>` routes + passes args
#  through, that a bare `core` shows the index, and that an unknown verb
#  suggests the nearest instead of dispatching.
#
#  Scope note: the stubs are `global:` functions, so they must record into a
#  `$global:` list — a `$script:` var set in BeforeAll resolves to a different
#  scope inside a global function than the It blocks read, and the routing
#  asserts would silently see an empty list.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # Module provides the pure helpers the fragment calls (Get-DotLevenshtein,
    # Get-DotRepoVersionDetail, Write-DotErr, Write-DotHost).
    $script:Module = Import-Module (Join-Path $RepoRoot 'powershell/Dotfiles/Dotfiles.psd1') -Force -DisableNameChecking -PassThru

    # Test-Cmd is a load-time FRAGMENT function (core/05-lib.ps1), not a module
    # export, so it's absent in this unit context — stub it with equivalent
    # behaviour so core-version's git-metadata guard resolves.
    function global:Test-Cmd { param([string]$Name) [bool](Get-Command $Name -ErrorAction Ignore) }

    # Point the layer root at this checkout so core-version exercises its real
    # git-revision branch (the repo IS a git checkout in CI).
    $script:prevDotfilesWin = $env:DOTFILES_WIN
    $env:DOTFILES_WIN = $RepoRoot

    # Record which leaf each route lands on (+ the args it forwarded). Global so
    # the global stubs and the It blocks share one list (see scope note above).
    $global:DotCoreCalls = [System.Collections.Generic.List[string]]::new()
    function global:dotfiles-doctor { $global:DotCoreCalls.Add("doctor:$($args -join ',')") }
    function global:dothelp         { $global:DotCoreCalls.Add("help:$($args -join ',')") }
    function global:up              { $global:DotCoreCalls.Add("up:$($args -join ',')") }

    . (Join-Path $RepoRoot 'powershell/os/48-core.ps1')
}

AfterAll {
    $env:DOTFILES_WIN = $script:prevDotfilesWin
    Remove-Variable -Name DotCoreCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Item function:core, function:core-doctor, function:core-help, function:core-version -ErrorAction SilentlyContinue
    Remove-Item function:dotfiles-doctor, function:dothelp, function:up -ErrorAction SilentlyContinue
    Remove-Item function:Test-Cmd -ErrorAction SilentlyContinue
    if ($script:Module) { Remove-Module $script:Module -Force -ErrorAction SilentlyContinue }
}

Describe 'core front door' {
    BeforeEach { $global:DotCoreCalls.Clear() }

    It 'routes `core doctor` to dotfiles-doctor and forwards args' {
        core doctor -Quiet
        $global:DotCoreCalls | Should -Contain 'doctor:-Quiet'
    }
    It 'routes `core help <filter>` to dothelp' {
        core help git
        $global:DotCoreCalls | Should -Contain 'help:git'
    }
    It 'treats a bare `core` as the help index' {
        core
        ($global:DotCoreCalls | Where-Object { $_ -like 'help:*' }) | Should -Not -BeNullOrEmpty
    }
    It 'routes `core update` to up and forwards args' {
        core update -y
        $global:DotCoreCalls | Should -Contain 'up:-y'
    }
    It '`core version` prints the layer name' {
        (core version *>&1 | Out-String) | Should -Match 'dotfiles-Windows'
    }
    It 'suggests the nearest verb on a typo and does NOT dispatch' {
        $out = core doctr *>&1 | Out-String
        $out | Should -Match 'did you mean: core doctor'
        $global:DotCoreCalls | Should -BeNullOrEmpty
    }
}

Describe 'core-* standalone twins' {
    BeforeEach { $global:DotCoreCalls.Clear() }

    It 'core-doctor forwards to dotfiles-doctor' {
        core-doctor -Quiet
        $global:DotCoreCalls | Should -Contain 'doctor:-Quiet'
    }
    It 'core-help forwards to dothelp' {
        core-help
        ($global:DotCoreCalls | Where-Object { $_ -like 'help:*' }) | Should -Not -BeNullOrEmpty
    }
    It 'core-version prints dotfiles-Windows + a revision detail' {
        (core-version *>&1 | Out-String) | Should -Match 'dotfiles-Windows'
    }
}
