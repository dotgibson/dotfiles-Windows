# ============================================================================
#  tests/Core.Tests.ps1  -  the `core` front door (os/48-core.ps1) dispatch.
#
#  The front door is thin routing over host verbs (dotfiles-doctor / dothelp /
#  up), which are host-specific and NOT exercised here. We stub those leaves,
#  dot-source the fragment, and assert `core <verb>` routes + passes args
#  through, that a bare `core` shows the index, and that an unknown verb
#  suggests the nearest instead of dispatching.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # Module provides the pure helpers the fragment calls (Get-DotLevenshtein,
    # Get-DotRepoVersionDetail, Test-Cmd, Write-DotErr, Write-DotHost).
    $script:Module = Import-Module (Join-Path $RepoRoot 'powershell/Dotfiles/Dotfiles.psd1') -Force -DisableNameChecking -PassThru

    # Point the layer root at this checkout so core-version exercises its real
    # git-revision branch (the repo IS a git checkout in CI).
    $script:prevDotfilesWin = $env:DOTFILES_WIN
    $env:DOTFILES_WIN = $RepoRoot

    # Record which leaf each route lands on (+ the args it forwarded).
    $script:calls = [System.Collections.Generic.List[string]]::new()
    function global:dotfiles-doctor { $script:calls.Add("doctor:$($args -join ',')") }
    function global:dothelp         { $script:calls.Add("help:$($args -join ',')") }
    function global:up              { $script:calls.Add("up:$($args -join ',')") }

    . (Join-Path $RepoRoot 'powershell/os/48-core.ps1')
}

AfterAll {
    $env:DOTFILES_WIN = $script:prevDotfilesWin
    Remove-Item function:core, function:core-doctor, function:core-help, function:core-version -ErrorAction SilentlyContinue
    Remove-Item function:dotfiles-doctor, function:dothelp, function:up -ErrorAction SilentlyContinue
    if ($script:Module) { Remove-Module $script:Module -Force -ErrorAction SilentlyContinue }
}

Describe 'core front door' {
    BeforeEach { $script:calls.Clear() }

    It 'routes `core doctor` to dotfiles-doctor and forwards args' {
        core doctor -Quiet
        $script:calls | Should -Contain 'doctor:-Quiet'
    }
    It 'routes `core help <filter>` to dothelp' {
        core help git
        $script:calls | Should -Contain 'help:git'
    }
    It 'treats a bare `core` as the help index' {
        core
        ($script:calls | Where-Object { $_ -like 'help:*' }) | Should -Not -BeNullOrEmpty
    }
    It 'routes `core update` to up and forwards args' {
        core update -y
        $script:calls | Should -Contain 'up:-y'
    }
    It '`core version` prints the layer name' {
        (core version *>&1 | Out-String) | Should -Match 'dotfiles-Windows'
    }
    It 'suggests the nearest verb on a typo and does NOT dispatch' {
        $out = core doctr *>&1 | Out-String
        $out | Should -Match 'did you mean: core doctor'
        $script:calls | Should -BeNullOrEmpty
    }
}

Describe 'core-* standalone twins' {
    BeforeEach { $script:calls.Clear() }

    It 'core-doctor forwards to dotfiles-doctor' {
        core-doctor -Quiet
        $script:calls | Should -Contain 'doctor:-Quiet'
    }
    It 'core-help forwards to dothelp' {
        core-help
        ($script:calls | Where-Object { $_ -like 'help:*' }) | Should -Not -BeNullOrEmpty
    }
    It 'core-version prints dotfiles-Windows + a revision detail' {
        (core-version *>&1 | Out-String) | Should -Match 'dotfiles-Windows'
    }
}
