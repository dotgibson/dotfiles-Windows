# ============================================================================
#  tests/WslBridge.Tests.ps1  -  pure host-layer logic from os/31-wsl-bridge.ps1.
#  The wsl-dependent verbs aren't exercised; the path translation is.
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    # 00-aliases defines Test-Cmd, which the fragment references at load time.
    . (Join-Path $RepoRoot 'powershell/core/00-aliases.ps1')
    . (Join-Path $RepoRoot 'powershell/os/31-wsl-bridge.ps1')
}

Describe 'ConvertTo-WslPath' {
    It 'maps a C: path to /mnt/c' {
        ConvertTo-WslPath 'C:\Users\me\src' | Should -Be '/mnt/c/Users/me/src'
    }
    It 'lower-cases the drive letter' {
        ConvertTo-WslPath 'D:\Repo' | Should -Be '/mnt/d/Repo'
    }
    It 'handles a forward-slash drive path' {
        ConvertTo-WslPath 'E:/data/x' | Should -Be '/mnt/e/data/x'
    }
    It 'returns null for a non-drive path (UNC)' {
        ConvertTo-WslPath '\\server\share' | Should -BeNullOrEmpty
    }
    It 'returns null for an already-translated path' {
        ConvertTo-WslPath '/mnt/c/already' | Should -BeNullOrEmpty
    }
}
