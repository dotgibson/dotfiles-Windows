# ============================================================================
#  tests/Integration.Tests.ps1  -  install -> uninstall round-trip on a real
#  (temp) filesystem. The other suites unit-test pure functions; this one wires
#  actual symlinks from the shared link plan and tears them back down, exercising
#  the real predicates (Test-SymlinkCurrent, Test-LinkIntoRepo) end-to-end so a
#  wiring/teardown regression can't pass on green unit tests alone.
#
#  Needs symlink creation privileges; the GitHub windows-latest runner (and Linux)
#  both allow it — the same New-Item -SymbolicLink the Uninstall suite already uses.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_INSTALL_LIBONLY   = '1'
    $env:DOTFILES_UNINSTALL_LIBONLY = '1'
    . (Join-Path $RepoRoot 'powershell/core/05-lib.ps1')   # Get-DotfilesLinkPlan
    . (Join-Path $RepoRoot 'install.ps1')                  # Test-SymlinkCurrent
    . (Join-Path $RepoRoot 'uninstall.ps1')                # Test-LinkIntoRepo

    # A self-contained fake world: a fake repo with the target files, and fake
    # HOME / LOCALAPPDATA / Documents roots the plan links into.
    $script:World = Join-Path ([IO.Path]::GetTempPath()) ("rt-" + [guid]::NewGuid().ToString('N'))
    $script:Repo  = Join-Path $script:World 'repo'
    $script:Home  = Join-Path $script:World 'home'
    $script:Local = Join-Path $script:World 'local'
    $script:Docs  = Join-Path $script:World 'docs'
    foreach ($d in $script:Repo, $script:Home, $script:Local, $script:Docs) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }

    $script:Plan = Get-DotfilesLinkPlan -RepoRoot $script:Repo -HomeDir $script:Home `
        -LocalAppData $script:Local -Documents $script:Docs

    # Materialize each target inside the fake repo so the links have something to
    # point at (a file for file-targets, a dir for the nvim/scripts dir-targets).
    foreach ($row in $script:Plan) {
        $parent = Split-Path -Parent $row.Target
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        if ($row.Target -match '\.(ps1|json|conf|gitconfig|gitignore_global)$' -or (Split-Path -Leaf $row.Target) -eq 'config') {
            'target' | Set-Content -LiteralPath $row.Target
        } else {
            New-Item -ItemType Directory -Force -Path $row.Target | Out-Null
        }
    }
}

AfterAll {
    if ($script:World -and (Test-Path $script:World)) { Remove-Item $script:World -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:DOTFILES_INSTALL_LIBONLY, Env:DOTFILES_UNINSTALL_LIBONLY -ErrorAction SilentlyContinue
}

Describe 'install -> uninstall round-trip' {
    It 'wires every planned link as a symlink into the repo' {
        foreach ($row in $script:Plan) {
            $parent = Split-Path -Parent $row.Link
            if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            New-Item -ItemType SymbolicLink -Path $row.Link -Target $row.Target -Force | Out-Null

            # install's idempotency predicate must see the freshly-made link as current,
            # and uninstall's safety predicate must recognise it as one of ours.
            Test-SymlinkCurrent -Link $row.Link -Target $row.Target | Should -BeTrue
            Test-LinkIntoRepo  -Link $row.Link -Root   $script:Repo | Should -BeTrue
        }
    }

    It 'leaves a real user file alone (Test-LinkIntoRepo is false for it)' {
        $real = (Join-Path $script:Home '.gitconfig')   # overwrite the link with a real file
        Remove-Item -LiteralPath $real -Force -ErrorAction SilentlyContinue
        'my own config' | Set-Content -LiteralPath $real
        Test-LinkIntoRepo -Link $real -Root $script:Repo | Should -BeFalse
        # re-link it so the teardown step below has a link to remove again
        New-Item -ItemType SymbolicLink -Path $real -Target (Join-Path $script:Repo 'git\.gitconfig') -Force | Out-Null
    }

    It 'removes exactly the links that point into the repo' {
        $removed = 0
        foreach ($link in (Get-DotfilesLinkMap -HomeDir $script:Home -LocalAppData $script:Local -Documents $script:Docs)) {
            if (Test-LinkIntoRepo -Link $link -Root $script:Repo) {
                Remove-Item -LiteralPath $link -Force -Recurse -ErrorAction SilentlyContinue
                $removed++
            }
        }
        $removed | Should -Be $script:Plan.Count
        foreach ($row in $script:Plan) { Test-Path -LiteralPath $row.Link | Should -BeFalse }
    }
}
