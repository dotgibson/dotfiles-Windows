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
    It 'treats a bare string as an unpinned id' {
        $s = ConvertTo-DotWingetSpec 'Git.Git'
        $s.Id | Should -Be 'Git.Git'; $s.Version | Should -BeNullOrEmpty
    }
    It 'reads id + version from an object entry' {
        $s = ConvertTo-DotWingetSpec ([pscustomobject]@{ id = 'Git.Git'; version = '2.45.0' })
        $s.Id | Should -Be 'Git.Git'; $s.Version | Should -Be '2.45.0'
    }
}

Describe 'Get-PackagesUsage' {
    It 'documents every public switch' {
        $u = (Get-PackagesUsage) -join "`n"
        foreach ($flag in '-SkipScoop', '-SkipWinget', '-Help') {
            $u | Should -Match ([regex]::Escape($flag))
        }
    }
}
