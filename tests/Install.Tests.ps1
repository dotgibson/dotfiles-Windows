# ============================================================================
#  tests/Install.Tests.ps1  -  install.ps1 helpers (dot-sourced library-only).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_INSTALL_LIBONLY = '1'
    . (Join-Path $RepoRoot 'install.ps1')
    $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) ("lnktest-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Tmp | Out-Null
}
AfterAll {
    if ($script:Tmp -and (Test-Path $script:Tmp)) { Remove-Item $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:DOTFILES_INSTALL_LIBONLY -ErrorAction SilentlyContinue
}

Describe 'Test-SymlinkCurrent' {
    BeforeAll {
        $script:Target = Join-Path $script:Tmp 'target.txt'; 'hi' | Set-Content $script:Target
        $script:Other  = Join-Path $script:Tmp 'other.txt';  'no' | Set-Content $script:Other
        $script:Link   = Join-Path $script:Tmp 'link.txt'
    }
    It 'is false when the link does not exist' {
        Test-SymlinkCurrent -Link $script:Link -Target $script:Target | Should -BeFalse
    }
    It 'is true for a symlink pointing at the target' {
        New-Item -ItemType SymbolicLink -Path $script:Link -Target $script:Target -Force | Out-Null
        Test-SymlinkCurrent -Link $script:Link -Target $script:Target | Should -BeTrue
    }
    It 'is false when the symlink points elsewhere' {
        Test-SymlinkCurrent -Link $script:Link -Target $script:Other | Should -BeFalse
    }
    It 'is false for a real (non-link) file' {
        Test-SymlinkCurrent -Link $script:Target -Target $script:Target | Should -BeFalse
    }
}

Describe 'Get-InstallSummaryLines' {
    It 'renders all four tally categories' {
        $lines = Get-InstallSummaryLines -Stats ([ordered]@{ linked = 3; copied = 0; skipped = 2; backedup = 1 })
        $lines.Count | Should -Be 4
        ($lines -join "`n") | Should -Match 'linked   : 3'
        ($lines -join "`n") | Should -Match 'skipped  : 2'
        ($lines -join "`n") | Should -Match 'backed up: 1'
    }
}

Describe 'Get-DotLogsToPrune' {
    BeforeAll {
        # 13 fake logs with increasing timestamps; newest should be kept.
        $script:Logs = 1..13 | ForEach-Object {
            [pscustomobject]@{ Name = "install-$_.log"; FullName = "C:\logs\install-$_.log"; LastWriteTime = (Get-Date).AddMinutes($_) }
        }
    }
    It 'returns nothing when at or under the keep count' {
        Get-DotLogsToPrune ($script:Logs | Select-Object -First 5) -Keep 10 | Should -BeNullOrEmpty
    }
    It 'prunes everything except the newest Keep' {
        $pruned = Get-DotLogsToPrune $script:Logs -Keep 10
        @($pruned).Count | Should -Be 3
        # the three OLDEST (smallest minute offsets) are the ones pruned
        ($pruned.Name | Sort-Object) | Should -Be @('install-1.log', 'install-2.log', 'install-3.log')
    }
    It 'handles an empty/null input' {
        Get-DotLogsToPrune @()   -Keep 10 | Should -BeNullOrEmpty
        Get-DotLogsToPrune $null -Keep 10 | Should -BeNullOrEmpty
    }
}

Describe 'Get-DotRedactedTranscript' {
    It 'redacts a line carrying a secret and keeps ordinary lines' {
        $out = Get-DotRedactedTranscript @('cd C:\src', 'export GH_TOKEN=ghp_secret', 'll -a')
        ($out -join "`n") | Should -Match 'cd C:\\src'
        ($out -join "`n") | Should -Match 'll -a'
        ($out -join "`n") | Should -Match '<redacted'
        ($out -join "`n") | Should -Not -Match 'ghp_secret'
    }
    It 'returns empty for empty input' {
        Get-DotRedactedTranscript @() | Should -BeNullOrEmpty
    }
}

Describe 'Get-InstallUsage' {
    It 'documents every public switch' {
        $u = (Get-InstallUsage) -join "`n"
        foreach ($flag in '-SkipPackages', '-DryRun', '-NonInteractive', '-Yes', '-Help') {
            $u | Should -Match ([regex]::Escape($flag))
        }
    }
}
