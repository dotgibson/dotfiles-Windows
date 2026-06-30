# ============================================================================
#  tests/NvimParity.Tests.ps1  -  pure helpers behind the nvim<->Core gate (B1).
#  The clone/diff orchestration in Assert-NvimParity.ps1 runs only in CI (needs
#  network); these cover the offline-testable logic: .core-ref parsing, tree
#  hashing + exclusions, and the diff.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_NVIMPARITY_LIBONLY = '1'
    . (Join-Path $RepoRoot 'tests/Assert-NvimParity.ps1')
}
AfterAll { Remove-Item Env:DOTFILES_NVIMPARITY_LIBONLY -ErrorAction SilentlyContinue }

Describe 'Get-CoreRefField' {
    BeforeAll {
        $script:Ref = @(
            '# comment line',
            'source = https://github.com/Gerrrt/dotfiles-core.git',
            'branch = main',
            'commit = abc123def456',
            'tag    = v2.0.0',
            'date   = 2026-06-01'
        )
    }
    It 'reads a field value' {
        Get-CoreRefField $script:Ref 'commit' | Should -Be 'abc123def456'
    }
    It 'tolerates extra spacing around the = ' {
        Get-CoreRefField $script:Ref 'date' | Should -Be '2026-06-01'
    }
    It 'reads the release tag field (fleet-drift label)' {
        Get-CoreRefField $script:Ref 'tag' | Should -Be 'v2.0.0'
    }
    It 'returns $null for an absent key' {
        Get-CoreRefField $script:Ref 'nope' | Should -BeNullOrEmpty
    }
}

Describe 'Test-DotGitSha' {
    It 'accepts a short or full hex SHA' {
        Test-DotGitSha 'abc1234'                                  | Should -BeTrue
        Test-DotGitSha 'aabbccddeeff00112233445566778899aabbccdd' | Should -BeTrue
    }
    It 'rejects non-SHA, option-like, or empty values' {
        Test-DotGitSha '--upload-pack=evil' | Should -BeFalse
        Test-DotGitSha 'main'               | Should -BeFalse
        Test-DotGitSha 'zzzzzzz'            | Should -BeFalse
        Test-DotGitSha ''                   | Should -BeFalse
    }
}

Describe 'Resolve-CoreRemote' {
    BeforeAll {
        $script:Allow = @('https://github.com/Gerrrt/dotfiles-core.git')
        $script:Fallback = 'https://github.com/Gerrrt/dotfiles-core.git'
    }
    It 'uses the source when it is allowlisted' {
        Resolve-CoreRemote -Source 'https://github.com/Gerrrt/dotfiles-core.git' -Allowed $script:Allow -Fallback 'FB' |
            Should -Be 'https://github.com/Gerrrt/dotfiles-core.git'
    }
    It 'falls back for a non-allowlisted (content-controlled) source' {
        Resolve-CoreRemote -Source 'https://evil.example/x.git' -Allowed $script:Allow -Fallback 'FB' | Should -Be 'FB'
    }
    It 'falls back for an empty/local source' {
        Resolve-CoreRemote -Source '' -Allowed $script:Allow -Fallback 'FB' | Should -Be 'FB'
    }
}

Describe 'Get-NvimParityDiff' {
    It 'is in sync for identical maps' {
        $d = Get-NvimParityDiff -Local @{ 'a.lua' = 'H1' } -Core @{ 'a.lua' = 'H1' }
        $d.InSync | Should -BeTrue
    }
    It 'flags a changed file (same path, different hash)' {
        $d = Get-NvimParityDiff -Local @{ 'a.lua' = 'H1' } -Core @{ 'a.lua' = 'H2' }
        $d.Changed | Should -Contain 'a.lua'; $d.InSync | Should -BeFalse
    }
    It 'flags a file missing from the vendored tree' {
        $d = Get-NvimParityDiff -Local @{} -Core @{ 'new.lua' = 'H' }
        $d.Missing | Should -Contain 'new.lua'; $d.InSync | Should -BeFalse
    }
    It 'flags a file that exists only in the vendored tree' {
        $d = Get-NvimParityDiff -Local @{ 'stale.lua' = 'H' } -Core @{}
        $d.Extra | Should -Contain 'stale.lua'; $d.InSync | Should -BeFalse
    }
    It 'treats $null maps as empty' {
        (Get-NvimParityDiff -Local $null -Core $null).InSync | Should -BeTrue
    }
}

Describe 'Get-NvimTreeHashes' {
    BeforeAll {
        $script:Tree = Join-Path $TestDrive 'nvim'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Tree 'lua/cfg') | Out-Null
        Set-Content (Join-Path $script:Tree 'init.lua')        'return 1'
        Set-Content (Join-Path $script:Tree 'lua/cfg/o.lua')   'return 2'
        Set-Content (Join-Path $script:Tree 'lazy-lock.json')  '{}'       # synced -> included
        Set-Content (Join-Path $script:Tree '.core-ref')       'commit = x'  # excluded
    }
    It 'hashes real files under relative, posix-style keys' {
        $h = Get-NvimTreeHashes $script:Tree
        $h.Keys | Should -Contain 'init.lua'
        $h.Keys | Should -Contain 'lua/cfg/o.lua'
        $h['init.lua'] | Should -Match '^[A-F0-9]{64}$'
    }
    It 'includes lazy-lock.json (cross-platform plugin pins, synced from Core) but excludes .core-ref' {
        $h = Get-NvimTreeHashes $script:Tree
        $h.Keys | Should -Contain 'lazy-lock.json'
        $h.Keys | Should -Not -Contain '.core-ref'
    }
    It 'returns an empty map for a non-existent root' {
        (Get-NvimTreeHashes (Join-Path $TestDrive 'nope')).Count | Should -Be 0
    }
}
