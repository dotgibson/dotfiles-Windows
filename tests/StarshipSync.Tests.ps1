# ============================================================================
#  tests/StarshipSync.Tests.ps1  -  starship-sync.ps1 pure ref resolver
#  (library-only). Covers the reproducible-pin option (-Ref) without cloning.
#  Mirror of NvimSync.Tests.ps1.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_STARSHIPSYNC_LIBONLY = '1'
    . (Join-Path $RepoRoot 'starship-sync.ps1')
}
AfterAll { Remove-Item Env:DOTFILES_STARSHIPSYNC_LIBONLY -ErrorAction SilentlyContinue }

Describe 'Get-StarshipSyncRefPlan' {
    It 'syncs the branch tip when no ref is given' {
        $p = Get-StarshipSyncRefPlan -Branch 'main'
        $p.Mode   | Should -Be 'branch'
        $p.Target | Should -Be 'main'
    }
    It 'pins an exact ref, which wins over -Branch' {
        $p = Get-StarshipSyncRefPlan -Ref 'v2.1.0' -Branch 'main'
        $p.Mode   | Should -Be 'ref'
        $p.Target | Should -Be 'v2.1.0'
    }
    It 'rejects a ref that starts with a dash (option injection)' {
        { Get-StarshipSyncRefPlan -Ref '--upload-pack=evil' } | Should -Throw
    }
    It 'rejects -Ref combined with -CoreLocal' {
        { Get-StarshipSyncRefPlan -Ref 'abc1234' -CoreLocal 'C:\src\dotfiles-core' } | Should -Throw
    }
}
