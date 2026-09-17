# ============================================================================
#  tests/NvimParity.Tests.ps1  -  pure helpers behind the nvim parity gate (B1).
#  The clone/diff orchestration in Assert-NvimParity.ps1 runs only in CI (needs
#  network); these cover the offline-testable logic: nvim.lock parsing, tree
#  hashing, the repo allowlist, and the diff.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_NVIMPARITY_LIBONLY = '1'
    . (Join-Path $RepoRoot 'tests/Assert-NvimParity.ps1')
}
AfterAll { Remove-Item Env:DOTFILES_NVIMPARITY_LIBONLY -ErrorAction SilentlyContinue }

Describe 'Get-CoreRefField (the shared marker reader)' {
    BeforeAll {
        $script:Lock = @(
            '# comment line',
            'nvim_repo=dotgibson/dotfiles-nvim',
            'nvim_branch=main',
            'nvim_sha=abc123def456',
            'nvim_version=1.0.0',
            'nvim_tag=v1.0.0'
        )
        # The older `key = value` spelling starship/ and theme/ still use. One
        # reader has to serve both, or a marker format becomes a second parser.
        $script:SpacedRef = @(
            'commit = abc123def456',
            'tag    = v2.0.0',
            'date   = 2026-06-01'
        )
    }
    It 'reads a field written in nvim.lock''s key=value spelling' {
        Get-CoreRefField $script:Lock 'nvim_sha' | Should -Be 'abc123def456'
    }
    It 'reads the release tag (what fleet-drift labels the Windows row with)' {
        Get-CoreRefField $script:Lock 'nvim_tag' | Should -Be 'v1.0.0'
    }
    It 'reads the repo slug the clone allowlist is matched against' {
        Get-CoreRefField $script:Lock 'nvim_repo' | Should -Be 'dotgibson/dotfiles-nvim'
    }
    It 'still tolerates the spaced `key = value` spelling' {
        Get-CoreRefField $script:SpacedRef 'commit' | Should -Be 'abc123def456'
        Get-CoreRefField $script:SpacedRef 'tag'    | Should -Be 'v2.0.0'
    }
    It 'does not let a key match a longer one that starts the same way' {
        # `nvim_sha` must not be answered by `nvim_shafoo`, and more to the point
        # `nvim_tag` must not be satisfied by a line for some other key.
        Get-CoreRefField @('nvim_shafoo=zzz') 'nvim_sha' | Should -BeNullOrEmpty
    }
    It 'returns $null for an absent key' {
        Get-CoreRefField $script:Lock 'nope' | Should -BeNullOrEmpty
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

Describe 'Resolve-NvimRepo' {
    BeforeAll { $script:Allow = @('dotgibson/dotfiles-nvim') }
    It 'uses the recorded slug when it is allowlisted' {
        Resolve-NvimRepo -Repo 'dotgibson/dotfiles-nvim' -Allowed $script:Allow -Fallback 'FB' |
            Should -Be 'dotgibson/dotfiles-nvim'
    }
    It 'falls back for a non-allowlisted (PR-editable) slug' {
        Resolve-NvimRepo -Repo 'attacker/evil' -Allowed $script:Allow -Fallback 'FB' | Should -Be 'FB'
    }
    It 'falls back for an empty slug' {
        Resolve-NvimRepo -Repo '' -Allowed $script:Allow -Fallback 'FB' | Should -Be 'FB'
    }
    It 'does not accept a full URL that merely contains an allowlisted slug' {
        # The gate builds https://github.com/<slug>.git from this value, so anything
        # other than an exact slug match has to fall back — a value like
        # `evil.example/x#dotgibson/dotfiles-nvim` must not survive.
        Resolve-NvimRepo -Repo 'https://github.com/dotgibson/dotfiles-nvim.git' -Allowed $script:Allow -Fallback 'FB' |
            Should -Be 'FB'
    }
}

Describe 'Get-NvimParityDiff' {
    It 'is in sync for identical maps' {
        $d = Get-NvimParityDiff -Local @{ 'a.lua' = 'H1' } -Upstream @{ 'a.lua' = 'H1' }
        $d.InSync | Should -BeTrue
    }
    It 'flags a changed file (same path, different hash)' {
        $d = Get-NvimParityDiff -Local @{ 'a.lua' = 'H1' } -Upstream @{ 'a.lua' = 'H2' }
        $d.Changed | Should -Contain 'a.lua'; $d.InSync | Should -BeFalse
    }
    It 'flags a file missing from the vendored tree' {
        $d = Get-NvimParityDiff -Local @{} -Upstream @{ 'new.lua' = 'H' }
        $d.Missing | Should -Contain 'new.lua'; $d.InSync | Should -BeFalse
    }
    It 'flags a file that exists only in the vendored tree' {
        $d = Get-NvimParityDiff -Local @{ 'stale.lua' = 'H' } -Upstream @{}
        $d.Extra | Should -Contain 'stale.lua'; $d.InSync | Should -BeFalse
    }
    It 'treats $null maps as empty' {
        (Get-NvimParityDiff -Local $null -Upstream $null).InSync | Should -BeTrue
    }
}

Describe 'Get-NvimTreeHashes' {
    BeforeAll {
        $script:Tree = Join-Path $TestDrive 'nvim'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Tree 'lua/cfg') | Out-Null
        Set-Content (Join-Path $script:Tree 'init.lua')        'return 1'
        Set-Content (Join-Path $script:Tree 'lua/cfg/o.lua')   'return 2'
        Set-Content (Join-Path $script:Tree 'lazy-lock.json')  '{}'       # vendored -> included
    }
    It 'hashes real files under relative, posix-style keys' {
        $h = Get-NvimTreeHashes $script:Tree
        $h.Keys | Should -Contain 'init.lua'
        $h.Keys | Should -Contain 'lua/cfg/o.lua'
        $h['init.lua'] | Should -Match '^[A-F0-9]{64}$'
    }
    It 'includes lazy-lock.json (cross-platform plugin pins, vendored upstream)' {
        (Get-NvimTreeHashes $script:Tree).Keys | Should -Contain 'lazy-lock.json'
    }
    It 'excludes nothing by default — the vendored tree is byte-identical upstream' {
        # The pin used to live at nvim/.core-ref, inside the compared tree, so it had
        # to be excluded by name. Moving it to the repo root (dotfiles-core#1124) is
        # what lets the default exclusion set be empty; assert that, because a
        # re-introduced default would silently stop comparing a real file.
        $DefaultExclude | Should -BeNullOrEmpty
    }
    It 'still honours an explicit exclusion when one is passed' {
        Set-Content (Join-Path $script:Tree 'skipme.txt') 'x'
        $h = Get-NvimTreeHashes $script:Tree -Exclude @('skipme.txt')
        $h.Keys | Should -Not -Contain 'skipme.txt'
        $h.Keys | Should -Contain 'init.lua'
    }
    It 'returns an empty map for a non-existent root' {
        (Get-NvimTreeHashes (Join-Path $TestDrive 'nope')).Count | Should -Be 0
    }
}
