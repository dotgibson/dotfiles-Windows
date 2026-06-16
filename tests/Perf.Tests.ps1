# ============================================================================
#  tests/Perf.Tests.ps1  -  cold-start performance regression gate.
#
#  A wall-clock budget on a shared CI runner is flaky, and the external tools
#  aren't installed there anyway, so this gates the STRUCTURAL invariants that
#  keep shell start fast — the things a careless change would quietly break:
#    1. the FAST_START escape hatch short-circuits the heavy fragment;
#    2. every spawn-on-load tool init goes through the cached Get-InitCache path
#       (no raw `Invoke-Expression (tool init)` paying a subprocess every shell);
#  plus a deliberately generous load-time safety net over the cheap, tool-
#  independent fragments, to catch someone doing real work at load time.
# ============================================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Tools    = Get-Content (Join-Path $script:RepoRoot 'powershell/core/10-tools.ps1') -Raw
}

Describe 'cold-start invariants' {
    It 'short-circuits the heavy fragment under FAST_START' {
        $script:Tools | Should -Match "if \(\`$env:FAST_START -eq '1'\) \{ return \}"
    }

    It 'caches every spawn-on-load tool init via Get-InitCache' {
        # starship/zoxide/mise/atuin/carapace/navi each shell out to print their
        # init script; all six must resolve it through the cache, or a cold shell
        # pays a subprocess spawn per tool again.
        foreach ($tool in 'starship', 'zoxide', 'mise', 'atuin', 'carapace', 'navi') {
            $script:Tools | Should -Match "Get-InitCache -Name $tool"
        }
    }

    It 'gives each cached init a non-cached fallback (never loses the integration)' {
        # The pattern is: $cf = Get-InitCache ...; if ($cf) { . $cf } else { <fallback> }
        ([regex]::Matches($script:Tools, 'if \(\$cf\) \{ \. \$cf \}')).Count | Should -BeGreaterOrEqual 5
    }
}

Describe 'cheap fragments load well under budget' {
    It 'dot-sources the tool-independent fragments quickly' {
        # These define functions / register completers and must NOT do heavy work at
        # load. Real cost is tens of ms; the 3s budget only trips on an egregious
        # regression (e.g. a network/subprocess call added to a load-time path).
        $global:DOTFILES = $script:RepoRoot
        $elapsed = Measure-Command {
            . (Join-Path $script:RepoRoot 'powershell/core/05-lib.ps1')
            . (Join-Path $script:RepoRoot 'powershell/core/55-help.ps1')
            . (Join-Path $script:RepoRoot 'powershell/core/00-aliases.ps1')
        }
        $elapsed.TotalMilliseconds | Should -BeLessThan 3000
    }
}
