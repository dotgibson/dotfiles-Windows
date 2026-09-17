# ============================================================================
#  tests/NvimSync.Tests.ps1  -  nvim-sync.ps1's pure helpers (library-only).
#  Covers the ref resolver, the release picker and the repo-slug parser without
#  cloning or reaching the network.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_NVIMSYNC_LIBONLY = '1'
    . (Join-Path $RepoRoot 'nvim-sync.ps1')
    . (Join-Path $PSScriptRoot '_TestHelpers.ps1')
}
AfterAll { Remove-Item Env:DOTFILES_NVIMSYNC_LIBONLY -ErrorAction SilentlyContinue }

Describe 'Get-NvimSyncRefPlan' {
    It 'pins the newest RELEASE by default, not a branch tip' {
        # The behaviour change of dotfiles-core#1124: this repo used to track Core's
        # main. dotfiles-nvim publishes releases so its consumers can name one, and a
        # bare run must not silently vendor unreleased editor commits. Target is empty
        # because it is not knowable without asking the remote.
        $p = Get-NvimSyncRefPlan -Branch 'main'
        $p.Mode   | Should -Be 'release'
        $p.Target | Should -BeNullOrEmpty
    }
    It 'follows the branch tip only when asked explicitly' {
        $p = Get-NvimSyncRefPlan -Branch 'main' -FollowBranch
        $p.Mode   | Should -Be 'branch'
        $p.Target | Should -Be 'main'
    }
    It 'pins an exact ref, which wins over the release default' {
        $p = Get-NvimSyncRefPlan -Ref 'v1.4.0' -Branch 'main'
        $p.Mode   | Should -Be 'ref'
        $p.Target | Should -Be 'v1.4.0'
    }
    It 'reports a local clone as its own mode' {
        $p = Get-NvimSyncRefPlan -NvimLocal 'C:\src\dotfiles-nvim'
        $p.Mode   | Should -Be 'local'
        $p.Target | Should -Be 'C:\src\dotfiles-nvim'
    }
    It 'rejects a ref that starts with a dash (option injection)' {
        { Get-NvimSyncRefPlan -Ref '--upload-pack=evil' } | Should -Throw
    }
    It 'rejects -Ref combined with -NvimLocal' {
        { Get-NvimSyncRefPlan -Ref 'abc1234' -NvimLocal 'C:\src\dotfiles-nvim' } | Should -Throw
    }
    It 'rejects -Ref combined with -FollowBranch (pin vs moving tip)' {
        { Get-NvimSyncRefPlan -Ref 'abc1234' -FollowBranch } | Should -Throw
    }
}

Describe 'Get-LatestNvimRelease' {
    BeforeAll {
        # Shaped exactly like `git ls-remote --tags --refs` output: <sha>\t<ref>.
        $script:Ls = @(
            "$('1' * 40)`trefs/tags/v1",
            "$('2' * 40)`trefs/tags/v1.9.0",
            "$('3' * 40)`trefs/tags/v1.10.0",
            "$('4' * 40)`trefs/tags/v1.11.0-rc1",
            "$('5' * 40)`trefs/tags/v0.9.9"
        )
    }
    It 'orders NUMERICALLY, so v1.10.0 beats v1.9.0' {
        # A string sort puts v1.9.0 last and would pin the wrong release. This is the
        # same trap dotfiles-core's check-nvim-freshness.sh calls out as "no sort -V".
        Get-LatestNvimRelease -LsRemoteLine $script:Ls | Should -Be 'v1.10.0'
    }
    It 'ignores the moving major alias (v1)' {
        # dotfiles-nvim re-points `v1` at each release. A pin set to a tag that MOVES
        # means the same recorded string names a different commit after the next cut.
        Get-LatestNvimRelease -LsRemoteLine @("$('1' * 40)`trefs/tags/v1") | Should -BeNullOrEmpty
    }
    It 'ignores prereleases' {
        Get-LatestNvimRelease -LsRemoteLine @("$('4' * 40)`trefs/tags/v1.11.0-rc1") | Should -BeNullOrEmpty
    }
    It 'ignores branches and other non-tag refs' {
        Get-LatestNvimRelease -LsRemoteLine @("$('1' * 40)`trefs/heads/main") | Should -BeNullOrEmpty
    }
    It 'returns empty for a remote with no releases at all' {
        Get-LatestNvimRelease -LsRemoteLine @() | Should -BeNullOrEmpty
    }
    It 'crosses a major boundary correctly' {
        $ls = @("$('1' * 40)`trefs/tags/v1.99.99", "$('2' * 40)`trefs/tags/v2.0.0")
        Get-LatestNvimRelease -LsRemoteLine $ls | Should -Be 'v2.0.0'
    }
}

Describe 'Get-NvimRepoSlug' {
    It 'parses an https remote, with or without .git' {
        Get-NvimRepoSlug -Remote 'https://github.com/dotgibson/dotfiles-nvim.git' | Should -Be 'dotgibson/dotfiles-nvim'
        Get-NvimRepoSlug -Remote 'https://github.com/dotgibson/dotfiles-nvim'     | Should -Be 'dotgibson/dotfiles-nvim'
    }
    It 'parses an ssh remote' {
        Get-NvimRepoSlug -Remote 'git@github.com:dotgibson/dotfiles-nvim.git' | Should -Be 'dotgibson/dotfiles-nvim'
    }
    It 'returns empty for a local path or a non-GitHub host' {
        # The caller then keeps the canonical slug: the REPOSITORY is the same no
        # matter which transport the bytes arrived over, and the parity gate has to be
        # able to re-fetch the recorded commit from somewhere real.
        Get-NvimRepoSlug -Remote 'C:\src\dotfiles-nvim'      | Should -BeNullOrEmpty
        Get-NvimRepoSlug -Remote 'https://evil.example/x.git' | Should -BeNullOrEmpty
    }
}

Describe 'Get-NvimDescribeTag' {
    # The bug (#202): the old nvim/.core-ref recorded `tag = v4-19-g10ad221`. `v4` is a
    # MOVING major alias that tag-release.sh force-repoints on every cut, so the recorded
    # string silently changed meaning — re-running the same describe today yields
    # v4.15.1-19-g10ad221. `commit` was always right; only `tag` lied. dotfiles-nvim cuts
    # its releases with the same script shape and the same `v1` alias, so the hazard came
    # along with the source switch. These cases live here (not below the LIBONLY hook)
    # precisely because the old inline describe call was unreachable from Pester, which
    # is why a wrong value shipped unnoticed.
    It 'names the SPECIFIC release, not the moving major alias' {
        if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not on PATH'; return
        }
        $fx = New-DotCoreTagFixture -Release 'v9.9.9' -Alias 'v9' -Past 2
        try { Get-NvimDescribeTag -RepoPath $fx | Should -Match '^v9\.9\.9-2-g[0-9a-f]{7,}$' }
        finally { Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'covers a case a bare `describe --tags` gets WRONG' {
        # Guards the FIXTURE, not the code: if this ever stops returning the alias, the
        # fixture has stopped reproducing #202 and the assertion above proves nothing.
        if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not on PATH'; return
        }
        $fx = New-DotCoreTagFixture -Release 'v9.9.9' -Alias 'v9' -Past 2
        try { (& git -C $fx describe --tags HEAD 2>$null) | Should -Match '^v9-2-g' }
        finally { Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns the bare release when the vendored commit IS the release' {
        if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not on PATH'; return
        }
        $fx = New-DotCoreTagFixture -Release 'v9.9.9' -Alias 'v9' -Past 0
        try { Get-NvimDescribeTag -RepoPath $fx | Should -Be 'v9.9.9' }
        finally { Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns EMPTY when only the moving alias exists (absent beats wrong)' {
        # The deliberate trade Core states in sync-core.sh: nvim_tag is then left blank
        # and nvim_sha stays authoritative, rather than stamping a marker that moves out
        # from under us.
        if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not on PATH'; return
        }
        $fx = New-DotCoreTagFixture -Alias 'v9' -Past 2 -AliasOnly
        try { Get-NvimDescribeTag -RepoPath $fx | Should -BeNullOrEmpty }
        finally { Remove-Item $fx -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns empty (does not throw) for a path that is not a git repo' {
        # The -NvimLocal-on-a-plain-directory case: best-effort, never fatal.
        $d = New-DotTestTempDir -Prefix 'notgit'
        try { Get-NvimDescribeTag -RepoPath $d | Should -BeNullOrEmpty }
        finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
