# ============================================================================
#  tests/Serve.Tests.ps1  -  pure bind/url planning from core/20-functions.ps1.
#  The `serve` verb (LAN-IP probe + python spawn) isn't exercised; the decision
#  of which --bind args and which advertised URL is (Get-DotServePlan, B13).
# ============================================================================

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Module = Import-Module (Join-Path $RepoRoot 'powershell/Dotfiles/Dotfiles.psd1') -Force -DisableNameChecking -PassThru
}
AfterAll { if ($script:Module) { Remove-Module $script:Module -Force -ErrorAction SilentlyContinue } }

Describe 'Get-DotServePlan' {
    Context 'default (LAN) — the documented behaviour is unchanged' {
        It 'binds every interface (no --bind args)' {
            (Get-DotServePlan -Port 8000 -LanIp '192.168.1.50').BindArgs | Should -BeNullOrEmpty
        }
        It 'advertises the LAN URL when an IP was resolved' {
            $plan = Get-DotServePlan -Port 8080 -LanIp '192.168.1.50'
            $plan.Scope | Should -Be 'lan'
            $plan.Url   | Should -Be 'http://192.168.1.50:8080/'
        }
        It 'advertises no URL when no LAN IP was found (server still binds all)' {
            $plan = Get-DotServePlan -Port 8000 -LanIp ''
            $plan.Scope    | Should -Be 'lan'
            $plan.Url      | Should -BeNullOrEmpty
            $plan.BindArgs | Should -BeNullOrEmpty
        }
    }

    Context '-Local — the opt-in localhost-only escape hatch' {
        It 'binds 127.0.0.1 explicitly' {
            (Get-DotServePlan -Port 8000 -Local).BindArgs | Should -Be @('--bind', '127.0.0.1')
        }
        It 'advertises the loopback URL with the requested port' {
            $plan = Get-DotServePlan -Port 9000 -Local
            $plan.Scope | Should -Be 'local'
            $plan.Url   | Should -Be 'http://127.0.0.1:9000/'
        }
        It 'ignores any resolved LAN IP — localhost wins' {
            $plan = Get-DotServePlan -Port 8000 -Local -LanIp '192.168.1.50'
            $plan.Scope | Should -Be 'local'
            $plan.Url   | Should -Be 'http://127.0.0.1:8000/'
        }
    }

    It 'defaults to port 8000 like the serve verb' {
        (Get-DotServePlan -Local).Url | Should -Be 'http://127.0.0.1:8000/'
    }
}
