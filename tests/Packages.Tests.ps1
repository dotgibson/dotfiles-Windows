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

Describe 'Get-PackagesUsage' {
    It 'documents every public switch' {
        $u = (Get-PackagesUsage) -join "`n"
        foreach ($flag in '-SkipScoop', '-SkipWinget', '-Help') {
            $u | Should -Match ([regex]::Escape($flag))
        }
    }
}
