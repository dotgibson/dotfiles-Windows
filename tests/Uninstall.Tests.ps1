# ============================================================================
#  tests/Uninstall.Tests.ps1  -  uninstall.ps1 helpers (dot-sourced library-only).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_UNINSTALL_LIBONLY = '1'
    . (Join-Path $RepoRoot 'uninstall.ps1')
}
AfterAll {
    Remove-Item Env:DOTFILES_UNINSTALL_LIBONLY -ErrorAction SilentlyContinue
}

Describe 'Get-DotfilesLinkMap' {
    It 'derives link paths from the injected environment' {
        $map = Get-DotfilesLinkMap -HomeDir 'H:\me' -LocalAppData 'L:\app' -Documents 'D:\docs'
        $map | Should -Contain 'H:\me\.gitconfig'
        $map | Should -Contain 'L:\app\nvim'
        $map | Should -Contain 'D:\docs\PowerShell\Microsoft.PowerShell_profile.ps1'
    }
    It 'covers the same family of configs install.ps1 links' {
        $map = (Get-DotfilesLinkMap -HomeDir 'H:' -LocalAppData 'L:' -Documents 'D:') -join ';'
        foreach ($needle in 'psmux.conf', 'ssh\config', '.gitignore_global', 'settings.json') {
            $map | Should -Match ([regex]::Escape($needle))
        }
    }
}

Describe 'Test-LinkIntoRepo' {
    BeforeAll {
        $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) ("untest-" + [guid]::NewGuid().ToString('N'))
        $script:Repo = Join-Path $script:Tmp 'repo'
        New-Item -ItemType Directory -Force -Path $script:Repo | Out-Null
        $script:RepoFile = Join-Path $script:Repo 'thing.conf'; 'x' | Set-Content $script:RepoFile
        $script:Outside  = Join-Path $script:Tmp 'outside.conf'; 'y' | Set-Content $script:Outside
    }
    AfterAll { if (Test-Path $script:Tmp) { Remove-Item $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue } }

    It 'is false for a path that does not exist' {
        Test-LinkIntoRepo -Link (Join-Path $script:Tmp 'nope') -Root $script:Repo | Should -BeFalse
    }
    It 'is false for a real (non-link) file' {
        Test-LinkIntoRepo -Link $script:RepoFile -Root $script:Repo | Should -BeFalse
    }
    It 'is true for a symlink that points into the repo' {
        $link = Join-Path $script:Tmp 'into-repo'
        New-Item -ItemType SymbolicLink -Path $link -Target $script:RepoFile -Force | Out-Null
        Test-LinkIntoRepo -Link $link -Root $script:Repo | Should -BeTrue
    }
    It 'is false for a symlink that points outside the repo' {
        $link = Join-Path $script:Tmp 'out-link'
        New-Item -ItemType SymbolicLink -Path $link -Target $script:Outside -Force | Out-Null
        Test-LinkIntoRepo -Link $link -Root $script:Repo | Should -BeFalse
    }
}

Describe 'Get-UninstallUsage' {
    It 'documents every switch' {
        $u = (Get-UninstallUsage) -join "`n"
        foreach ($f in '-DryRun', '-RestoreBackups', '-Yes', '-Help') {
            $u | Should -Match ([regex]::Escape($f))
        }
    }
}
