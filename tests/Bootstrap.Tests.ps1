# ============================================================================
#  tests/Bootstrap.Tests.ps1  -  bootstrap.ps1 pure resolvers (library-only) +
#  the README integrity-pin drift gate (B10).
# ============================================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_BOOTSTRAP_LIBONLY = '1'
    . (Join-Path $script:RepoRoot 'bootstrap.ps1')
}
AfterAll { Remove-Item Env:DOTFILES_BOOTSTRAP_LIBONLY -ErrorAction SilentlyContinue }

Describe 'Get-BootstrapRepoUrl' {
    It 'defaults to the canonical repo when DOTFILES_REPO is unset' {
        Get-BootstrapRepoUrl -Repo '' | Should -Be 'https://github.com/Gerrrt/dotfiles-Windows.git'
    }
    It 'honours an explicit repo URL' {
        Get-BootstrapRepoUrl -Repo 'git@host:me/df.git' | Should -Be 'git@host:me/df.git'
    }
}

Describe 'Get-BootstrapTargetDir' {
    It 'falls back to ~/dotfiles-Windows when nothing is set' {
        Get-BootstrapTargetDir -Dir '' -WinVar '' -HomeDir '/h' | Should -Be (Join-Path '/h' 'dotfiles-Windows')
    }
    It 'uses DOTFILES_WIN when set and DOTFILES_DIR is not' {
        Get-BootstrapTargetDir -Dir '' -WinVar '/w' -HomeDir '/h' | Should -Be '/w'
    }
    It 'lets DOTFILES_DIR win over everything' {
        Get-BootstrapTargetDir -Dir '/d' -WinVar '/w' -HomeDir '/h' | Should -Be '/d'
    }
}

Describe 'Get-BootstrapGitAction' {
    It 'clones when the target has no .git' {
        Get-BootstrapGitAction -Dir (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())) | Should -Be 'clone'
    }
    It 'updates when the target is already a checkout' {
        Get-BootstrapGitAction -Dir $script:RepoRoot | Should -Be 'update'
    }
}

Describe 'Get-BootstrapInstallArgs' {
    It 'is empty when DOTFILES_BOOTSTRAP_ARGS is unset/blank' {
        @(Get-BootstrapInstallArgs -Raw '').Count   | Should -Be 0
        @(Get-BootstrapInstallArgs -Raw '   ').Count | Should -Be 0
    }
    It 'splits on whitespace into an argv array' {
        Get-BootstrapInstallArgs -Raw '-SkipPackages  -DryRun' | Should -Be @('-SkipPackages', '-DryRun')
    }
}

Describe 'bootstrap.ps1 integrity pin (B10)' {
    It 'README pins the current LF-normalized SHA-256 of bootstrap.ps1' {
        # The integrity-gated one-liner in the README only works if the published
        # hash tracks the script. Normalize CRLF->LF so the check is stable across
        # checkouts (git on Windows may materialize CRLF) and matches what GitHub
        # raw serves (LF) — i.e. exactly the bytes `irm` hands the user.
        $content = (Get-Content (Join-Path $script:RepoRoot 'bootstrap.ps1') -Raw) -replace "`r`n", "`n"
        $bytes   = [Text.Encoding]::UTF8.GetBytes($content)
        $actual  = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLower()

        $readme = Get-Content (Join-Path $script:RepoRoot 'README.md') -Raw
        $m = [regex]::Match($readme, 'bootstrap\.ps1 SHA-256 \(LF-normalized\):\s*([0-9a-f]{64})')
        $m.Success | Should -BeTrue -Because 'README should carry the "bootstrap.ps1 SHA-256 (LF-normalized): <hash>" marker'
        $m.Groups[1].Value | Should -Be $actual -Because 'update the README hash in the same commit whenever bootstrap.ps1 changes'
    }
}
