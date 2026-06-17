# ============================================================================
#  tests/Packages.Tests.ps1  -  Install-Packages helpers (library-only).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_PKG_LIBONLY = '1'
    . (Join-Path $RepoRoot 'packages/Install-Packages.ps1')
}
AfterAll { Remove-Item Env:DOTFILES_PKG_LIBONLY -ErrorAction SilentlyContinue }

Describe 'Get-WingetInstalledIds' {
    It 'extracts PackageIdentifiers from export JSON' {
        $json = '{ "Sources": [ { "Packages": [ {"PackageIdentifier":"Git.Git"}, {"PackageIdentifier":"Mozilla.Firefox"} ] } ] }'
        $ids = Get-WingetInstalledIds $json
        $ids | Should -HaveCount 2
        $ids | Should -Contain 'Git.Git'
    }
    It 'returns empty for blank input' {
        Get-WingetInstalledIds '' | Should -BeNullOrEmpty
    }
    It 'returns empty for malformed JSON (no throw)' {
        { Get-WingetInstalledIds 'not json {{' } | Should -Not -Throw
        Get-WingetInstalledIds 'not json {{' | Should -BeNullOrEmpty
    }
}

Describe 'Get-ScoopInstallToken' {
    It 'returns the bare name when unpinned' {
        Get-ScoopInstallToken ([pscustomobject]@{ Name = 'fzf'; Source = 'main' }) | Should -Be 'fzf'
    }
    It 'returns name@version when pinned' {
        Get-ScoopInstallToken ([pscustomobject]@{ Name = 'fzf'; Version = '0.54.0' }) | Should -Be 'fzf@0.54.0'
    }
}

Describe 'ConvertTo-DotWingetSpec' {
    It 'treats a bare string as an unpinned, ungrouped id' {
        $s = ConvertTo-DotWingetSpec 'Git.Git'
        $s.Id | Should -Be 'Git.Git'; $s.Version | Should -BeNullOrEmpty; $s.Group | Should -BeNullOrEmpty
    }
    It 'reads id + version from an object entry' {
        $s = ConvertTo-DotWingetSpec ([pscustomobject]@{ id = 'Git.Git'; version = '2.45.0' })
        $s.Id | Should -Be 'Git.Git'; $s.Version | Should -Be '2.45.0'
    }
    It 'reads an optional group tag (U3)' {
        $s = ConvertTo-DotWingetSpec ([pscustomobject]@{ id = 'Mozilla.Firefox'; group = 'gui' })
        $s.Id | Should -Be 'Mozilla.Firefox'; $s.Group | Should -Be 'gui'
    }
}

Describe 'Get-PackagesUsage' {
    It 'documents every public switch' {
        $u = (Get-PackagesUsage) -join "`n"
        foreach ($flag in '-SkipScoop', '-SkipWinget', '-Frozen', '-NonInteractive', '-Help') {
            $u | Should -Match ([regex]::Escape($flag))
        }
    }
}

# --- optional package groups (U3): pure policy helpers ------------------------
Describe 'Get-DotOptionalGroups' {
    It 'returns the distinct, sorted group tags present' {
        $entries = @(
            [pscustomobject]@{ Id = 'a'; Group = 'gui' }
            [pscustomobject]@{ Id = 'b'; Group = $null }
            [pscustomobject]@{ Id = 'c'; Group = 'gui' }
            [pscustomobject]@{ Id = 'd'; Group = 'sec' }
        )
        Get-DotOptionalGroups $entries | Should -Be @('gui', 'sec')
    }
    It 'returns empty when nothing is tagged' {
        Get-DotOptionalGroups @([pscustomobject]@{ Id = 'a'; Group = $null }) | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-DotGroupList / ConvertTo-DotGroupList' {
    It 'parses space- or comma-separated lists (lowercased, de-duped, sorted)' {
        ConvertFrom-DotGroupList 'GUI sec gui'  | Should -Be @('gui', 'sec')
        ConvertFrom-DotGroupList 'gui,sec'      | Should -Be @('gui', 'sec')
    }
    It 'treats blank and the "none" marker as an empty selection' {
        ConvertFrom-DotGroupList ''     | Should -BeNullOrEmpty
        ConvertFrom-DotGroupList 'none' | Should -BeNullOrEmpty
    }
    It 'formats a selection, emitting "none" when empty' {
        ConvertTo-DotGroupList @('sec', 'gui') | Should -Be 'gui sec'
        ConvertTo-DotGroupList @()             | Should -Be 'none'
    }
    It 'round-trips through both helpers' {
        ConvertFrom-DotGroupList (ConvertTo-DotGroupList @('gui')) | Should -Be @('gui')
        ConvertTo-DotGroupList (ConvertFrom-DotGroupList 'none')   | Should -Be 'none'
    }
}

Describe 'Test-DotGroupSelected' {
    It 'always installs a core (untagged) entry' {
        Test-DotGroupSelected -Group ''    -Selected @()      | Should -BeTrue
        Test-DotGroupSelected -Group $null -Selected @('gui') | Should -BeTrue
    }
    It 'installs a tagged entry only when its group is selected' {
        Test-DotGroupSelected -Group 'gui' -Selected @('gui') | Should -BeTrue
        Test-DotGroupSelected -Group 'gui' -Selected @('sec') | Should -BeFalse
        Test-DotGroupSelected -Group 'gui' -Selected @()      | Should -BeFalse
    }
}

Describe 'Set-DotGroupLine' {
    It 'appends a managed line to content that lacks one' {
        $out = Set-DotGroupLine -Content "# header`n" -Value 'gui'
        $out | Should -Match "(?m)^\`$env:DOTFILES_PKG_GROUPS = 'gui'"
        $out | Should -Match '# header'
    }
    It 'replaces an existing managed line instead of duplicating it' {
        $first  = Set-DotGroupLine -Content '' -Value 'gui'
        $second = Set-DotGroupLine -Content $first -Value 'none'
        @($second -split "`n" | Where-Object { $_ -match 'DOTFILES_PKG_GROUPS' }).Count | Should -Be 1
        $second | Should -Match "DOTFILES_PKG_GROUPS = 'none'"
    }
}

Describe 'Resolve-DotPackageGroupSelection' {
    AfterEach { Remove-Item Env:DOTFILES_PKG_GROUPS -ErrorAction SilentlyContinue }

    It 'returns empty when no optional groups exist' {
        Resolve-DotPackageGroupSelection -Available @() -NonInteractive $true -LocalPs1Path 'x' | Should -BeNullOrEmpty
    }
    It 'installs every group non-interactively (opt-out default)' {
        Resolve-DotPackageGroupSelection -Available @('gui', 'sec') -NonInteractive $true -LocalPs1Path 'x' |
            Should -Be @('gui', 'sec')
    }
    It 'honours a persisted selection, clamped to what exists' {
        $env:DOTFILES_PKG_GROUPS = 'gui gone'
        Resolve-DotPackageGroupSelection -Available @('gui', 'sec') -NonInteractive $false -LocalPs1Path 'x' |
            Should -Be @('gui')
    }
    It 'honours a persisted "none" as an empty selection' {
        $env:DOTFILES_PKG_GROUPS = 'none'
        Resolve-DotPackageGroupSelection -Available @('gui') -NonInteractive $false -LocalPs1Path 'x' |
            Should -BeNullOrEmpty
    }
}

# --- packages/PackageLock.ps1 (B4): pure lockfile helpers --------------------
# Dot-sourced transitively by Install-Packages.ps1 above, so the functions are in
# scope here.
Describe 'Read-PackageLock' {
    It 'parses scoop and winget version maps' {
        # generatedAt is a non-date sentinel on purpose: ConvertFrom-Json coerces an
        # ISO-8601 string into a [datetime] (which round-trips as 2026-...0000000Z),
        # and generatedAt is informational only. The version VALUES are explicitly
        # string-coerced in the helper, so they stay exact.
        $lock = Read-PackageLock '{ "generatedAt": "lock-stamp", "scoop": { "fzf": "0.54.0" }, "winget": { "Git.Git": "2.47.1" } }'
        $lock.Scoop['fzf']      | Should -Be '0.54.0'
        $lock.Winget['Git.Git'] | Should -Be '2.47.1'
        $lock.GeneratedAt       | Should -Be 'lock-stamp'
    }
    It 'is case-insensitive on lookups' {
        (Read-PackageLock '{ "scoop": { "FZF": "1.0" } }').Scoop['fzf'] | Should -Be '1.0'
    }
    It 'returns empty maps for blank or malformed input (no throw)' {
        (Read-PackageLock '').Scoop          | Should -BeNullOrEmpty
        { Read-PackageLock 'not json {{' }   | Should -Not -Throw
        (Read-PackageLock 'not json {{').Winget | Should -BeNullOrEmpty
    }
}

Describe 'Get-LockedVersion' {
    It 'returns the version when present (case-insensitive)' {
        Get-LockedVersion -Map @{ 'Git.Git' = '2.47.1' } -Name 'git.git' | Should -Be '2.47.1'
    }
    It 'returns $null for a miss, a null map, or an empty name' {
        Get-LockedVersion -Map @{ a = '1' } -Name 'b' | Should -BeNullOrEmpty
        Get-LockedVersion -Map $null -Name 'a'        | Should -BeNullOrEmpty
        Get-LockedVersion -Map @{ a = '1' } -Name ''   | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-ScoopExport' {
    It 'reads name/version from the modern { apps: [...] } shape' {
        $m = ConvertFrom-ScoopExport '{ "apps": [ { "Name": "fzf", "Version": "0.54.0" }, { "Name": "bat", "Version": "0.24.0" } ] }'
        $m['fzf'] | Should -Be '0.54.0'; $m['bat'] | Should -Be '0.24.0'
    }
    It 'reads the legacy bare-array shape' {
        (ConvertFrom-ScoopExport '[ { "Name": "jq", "Version": "1.7" } ]')['jq'] | Should -Be '1.7'
    }
    It 'skips entries without a version, and tolerates junk' {
        (ConvertFrom-ScoopExport '{ "apps": [ { "Name": "x" } ] }').Count | Should -Be 0
        { ConvertFrom-ScoopExport 'nope' } | Should -Not -Throw
    }
}

Describe 'ConvertFrom-WingetExport' {
    It 'reads id/version from the Sources/Packages shape' {
        $json = '{ "Sources": [ { "Packages": [ { "PackageIdentifier": "Git.Git", "Version": "2.47.1" } ] } ] }'
        (ConvertFrom-WingetExport $json)['Git.Git'] | Should -Be '2.47.1'
    }
    It 'skips non-version placeholders and empty versions' {
        $json = '{ "Sources": [ { "Packages": [ { "PackageIdentifier": "A", "Version": "Unknown" }, { "PackageIdentifier": "B", "Version": "" }, { "PackageIdentifier": "C", "Version": "Latest" } ] } ] }'
        (ConvertFrom-WingetExport $json).Count | Should -Be 0
    }
}

Describe 'Get-PackageLockDrift' {
    It 'reports nothing when the manifest and lock agree' {
        $d = Get-PackageLockDrift -DesiredNames @('a', 'b') -LockMap @{ a = '1'; b = '2' }
        $d.InSync | Should -BeTrue
    }
    It 'flags a desired-but-unlocked name as Missing' {
        $d = Get-PackageLockDrift -DesiredNames @('a', 'b') -LockMap @{ a = '1' }
        $d.Missing | Should -Contain 'b'; $d.InSync | Should -BeFalse
    }
    It 'flags a locked-but-undesired name as Orphan' {
        $d = Get-PackageLockDrift -DesiredNames @('a') -LockMap @{ a = '1'; old = '9' }
        $d.Orphan | Should -Contain 'old'; $d.InSync | Should -BeFalse
    }
}

Describe 'New-PackageLockObject' {
    It 'sorts keys and carries the injected timestamp' {
        $o = New-PackageLockObject -Scoop @{ zoxide = '1'; bat = '2' } -Winget @{} -GeneratedAt 'TS'
        $o.generatedAt | Should -Be 'TS'
        @($o.scoop.Keys) | Should -Be @('bat', 'zoxide')   # sorted
    }
    It 'treats a $null section as an empty map (no throw)' {
        { New-PackageLockObject -Scoop $null -Winget $null -GeneratedAt 'TS' } | Should -Not -Throw
        $o = New-PackageLockObject -Scoop $null -Winget $null -GeneratedAt 'TS'
        @($o.scoop.Keys).Count | Should -Be 0
    }
}

# --- drift gate: enforced once packages.lock.json is committed (B4) -----------
Describe 'packages.lock.json drift' {
    It 'covers exactly the managed manifest set (skipped until the lock exists)' {
        $lockPath = Join-Path $RepoRoot 'packages/packages.lock.json'
        if (-not (Test-Path $lockPath)) {
            Set-ItResult -Skipped -Because 'no packages.lock.json yet — run Update-PackageLock.ps1 on Windows and commit it'
            return
        }
        $lock = Read-PackageLock (Get-Content $lockPath -Raw)
        $scoop  = Get-Content (Join-Path $RepoRoot 'packages/scoopfile.json') -Raw | ConvertFrom-Json
        $winget = Get-Content (Join-Path $RepoRoot 'packages/winget.json')  -Raw | ConvertFrom-Json
        $scoopNames = @($scoop.apps | ForEach-Object { $_.Name })
        $wingetIds  = @($winget.packages | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } })

        $sd = Get-PackageLockDrift -DesiredNames $scoopNames -LockMap $lock.Scoop
        $wd = Get-PackageLockDrift -DesiredNames $wingetIds  -LockMap $lock.Winget
        $sd.Missing | Should -BeNullOrEmpty -Because "scoop apps added without re-locking: $($sd.Missing -join ', ')"
        $sd.Orphan  | Should -BeNullOrEmpty -Because "scoop apps removed from the manifest but still locked: $($sd.Orphan -join ', ')"
        $wd.Missing | Should -BeNullOrEmpty -Because "winget ids added without re-locking: $($wd.Missing -join ', ')"
        $wd.Orphan  | Should -BeNullOrEmpty -Because "winget ids removed from the manifest but still locked: $($wd.Orphan -join ', ')"
    }
}
