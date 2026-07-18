# ============================================================================
#  tests/Install.Tests.ps1  -  install.ps1 helpers (dot-sourced library-only).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $env:DOTFILES_INSTALL_LIBONLY = '1'
    . (Join-Path $RepoRoot 'install.ps1')
    . (Join-Path $PSScriptRoot '_TestHelpers.ps1')
    $script:Tmp = New-DotTestTempDir -Prefix 'lnktest'
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

Describe 'Test-CopyCurrent' {
    BeforeEach {
        $script:Cc = Join-Path $script:Tmp ('cc-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Cc | Out-Null
    }
    AfterEach { Remove-Item $script:Cc -Recurse -Force -ErrorAction SilentlyContinue }

    It 'is false when the link does not exist' {
        $t = Join-Path $script:Cc 't.txt'; 'hi' | Set-Content $t
        Test-CopyCurrent -Link (Join-Path $script:Cc 'missing.txt') -Target $t | Should -BeFalse
    }
    It 'is true when a file copy matches the target byte-for-byte' {
        $t = Join-Path $script:Cc 't.txt'; 'same content' | Set-Content $t
        $l = Join-Path $script:Cc 'l.txt'; Copy-Item $t $l
        Test-CopyCurrent -Link $l -Target $t | Should -BeTrue
    }
    It 'is false when the file copy differs from the target' {
        $t = Join-Path $script:Cc 't.txt'; 'original' | Set-Content $t
        $l = Join-Path $script:Cc 'l.txt'; 'edited'   | Set-Content $l
        Test-CopyCurrent -Link $l -Target $t | Should -BeFalse
    }
    It 'is false when one side is a file and the other a directory' {
        $t = Join-Path $script:Cc 't.txt'; 'x' | Set-Content $t
        $d = Join-Path $script:Cc 'dir'; New-Item -ItemType Directory -Force -Path $d | Out-Null
        Test-CopyCurrent -Link $d -Target $t | Should -BeFalse
    }
    It 'is true for two directory trees with identical content' {
        $src = Join-Path $script:Cc 'src'; $dst = Join-Path $script:Cc 'dst'
        New-Item -ItemType Directory -Force -Path (Join-Path $src 'sub') | Out-Null
        'a' | Set-Content (Join-Path $src 'a.txt'); 'b' | Set-Content (Join-Path $src 'sub/b.txt')
        Copy-Item $src $dst -Recurse
        Test-CopyCurrent -Link $dst -Target $src | Should -BeTrue
    }
    It 'is false when a nested file differs' {
        $src = Join-Path $script:Cc 'src'; $dst = Join-Path $script:Cc 'dst'
        New-Item -ItemType Directory -Force -Path (Join-Path $src 'sub') | Out-Null
        'a' | Set-Content (Join-Path $src 'a.txt'); 'b' | Set-Content (Join-Path $src 'sub/b.txt')
        Copy-Item $src $dst -Recurse
        'changed' | Set-Content (Join-Path $dst 'sub/b.txt')
        Test-CopyCurrent -Link $dst -Target $src | Should -BeFalse
    }
    It 'is false when the destination tree has an extra file' {
        $src = Join-Path $script:Cc 'src'; $dst = Join-Path $script:Cc 'dst'
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        'a' | Set-Content (Join-Path $src 'a.txt')
        Copy-Item $src $dst -Recurse
        'extra' | Set-Content (Join-Path $dst 'extra.txt')
        Test-CopyCurrent -Link $dst -Target $src | Should -BeFalse
    }
    It 'is false when only an EMPTY subdirectory is added (no file changes)' {
        $src = Join-Path $script:Cc 'src'; $dst = Join-Path $script:Cc 'dst'
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        'a' | Set-Content (Join-Path $src 'a.txt')
        Copy-Item $src $dst -Recurse
        New-Item -ItemType Directory -Force -Path (Join-Path $dst 'emptydir') | Out-Null
        Test-CopyCurrent -Link $dst -Target $src | Should -BeFalse
    }
}

Describe 'Get-InstallSummaryLines' {
    It 'renders all four tally categories' {
        $lines = Get-InstallSummaryLines -Stats ([ordered]@{ linked = 3; copied = 0; skipped = 2; backedup = 1 })
        # Exact, ordered output — covers the previously-unchecked 'copied' line and
        # the 'skipped' "(already correct)" suffix, not just three loose substrings.
        $lines | Should -Be @(
            'linked   : 3'
            'copied   : 0'
            'skipped  : 2  (already correct)'
            'backed up: 1'
        )
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
