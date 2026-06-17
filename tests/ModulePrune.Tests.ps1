# ============================================================================
#  tests/ModulePrune.Tests.ps1  -  Get-DotModulePrunePlan (Modules.Helpers, B11).
#  The pure reconcile logic behind `modules-localize -Prune`. The Remove-Item and
#  directory discovery live in the os/30-windows.ps1 fragment; this covers the
#  decision.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $RepoRoot 'powershell/Dotfiles/Modules.Helpers.ps1')

    # Build an installed-entry like the fragment discovers from <Name>/<Version>/.
    function script:Mod($name, $ver) {
        [pscustomobject]@{ Name = $name; Version = $ver; Path = "store/$name/$ver" }
    }
}

Describe 'Get-DotModulePrunePlan' {
    It 'prunes the older version of a managed module, keeping the highest' {
        $installed = @( (Mod 'PSReadLine' '2.2.0'), (Mod 'PSReadLine' '2.3.0') )
        $plan = @(Get-DotModulePrunePlan -Installed $installed -ManagedNames @('PSReadLine'))
        $plan.Count        | Should -Be 1
        $plan[0].Version   | Should -Be '2.2.0'
        $plan[0].Path      | Should -Be 'store/PSReadLine/2.2.0'
    }

    It 'keeps the highest across several stale versions (semantic, not lexical)' {
        $installed = @( (Mod 'X' '2.9.0'), (Mod 'X' '2.10.0'), (Mod 'X' '2.2.0') )
        $plan = @(Get-DotModulePrunePlan -Installed $installed -ManagedNames @('X'))
        # 2.10.0 wins over 2.9.0 (would lose under a string sort); two older pruned.
        @($plan.Version | Sort-Object) | Should -Be @('2.2.0', '2.9.0')
    }

    It 'leaves a single-version managed module alone' {
        $plan = @(Get-DotModulePrunePlan -Installed @( (Mod 'PSFzf' '2.4.0') ) -ManagedNames @('PSFzf'))
        $plan.Count | Should -Be 0
    }

    It 'never touches a module outside the managed set' {
        $installed = @( (Mod 'UserMod' '1.0.0'), (Mod 'UserMod' '2.0.0') )
        $plan = @(Get-DotModulePrunePlan -Installed $installed -ManagedNames @('PSReadLine'))
        $plan.Count | Should -Be 0
    }

    It 'is case-insensitive on the managed-name match' {
        $installed = @( (Mod 'PSReadLine' '2.2.0'), (Mod 'PSReadLine' '2.3.0') )
        $plan = @(Get-DotModulePrunePlan -Installed $installed -ManagedNames @('psreadline'))
        $plan.Count | Should -Be 1
    }

    It 'does not prune when versions are not cleanly comparable (prerelease)' {
        $installed = @( (Mod 'Y' '2.0.0'), (Mod 'Y' '2.1.0-beta') )
        # only one parseable [version] -> nothing safely stale -> keep both
        $plan = @(Get-DotModulePrunePlan -Installed $installed -ManagedNames @('Y'))
        $plan.Count | Should -Be 0
    }

    It 'handles multiple managed modules independently' {
        $installed = @(
            (Mod 'A' '1.0.0'), (Mod 'A' '1.1.0'),
            (Mod 'B' '0.1.0'), (Mod 'B' '0.2.0'), (Mod 'B' '0.3.0')
        )
        $plan = @(Get-DotModulePrunePlan -Installed $installed -ManagedNames @('A', 'B'))
        $plan.Count | Should -Be 3   # A: 1 stale, B: 2 stale
    }

    It 'returns empty for empty input or an empty managed list' {
        @(Get-DotModulePrunePlan -Installed @() -ManagedNames @('A')).Count        | Should -Be 0
        @(Get-DotModulePrunePlan -Installed @( (Mod 'A' '1.0.0') ) -ManagedNames @()).Count | Should -Be 0
    }
}
