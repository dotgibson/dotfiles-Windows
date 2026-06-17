# ============================================================================
#  tests/NvimSync.Tests.ps1  -  nvim-sync.ps1 pure ref resolver (library-only).
#  Covers B1's reproducible-pin option (-Ref) without cloning anything.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_NVIMSYNC_LIBONLY = '1'
    . (Join-Path $RepoRoot 'nvim-sync.ps1')
}
AfterAll { Remove-Item Env:DOTFILES_NVIMSYNC_LIBONLY -ErrorAction SilentlyContinue }

Describe 'Get-NvimSyncRefPlan' {
    It 'syncs the branch tip when no ref is given' {
        $p = Get-NvimSyncRefPlan -Branch 'main'
        $p.Mode   | Should -Be 'branch'
        $p.Target | Should -Be 'main'
    }
    It 'pins an exact ref, which wins over -Branch' {
        $p = Get-NvimSyncRefPlan -Ref 'v1.4.0' -Branch 'main'
        $p.Mode   | Should -Be 'ref'
        $p.Target | Should -Be 'v1.4.0'
    }
    It 'rejects a ref that starts with a dash (option injection)' {
        { Get-NvimSyncRefPlan -Ref '--upload-pack=evil' } | Should -Throw
    }
    It 'rejects -Ref combined with -CoreLocal' {
        { Get-NvimSyncRefPlan -Ref 'abc1234' -CoreLocal 'C:\src\dotfiles-core' } | Should -Throw
    }
}
