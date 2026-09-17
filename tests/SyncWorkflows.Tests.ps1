# ============================================================================
#  tests/SyncWorkflows.Tests.ps1  -  the three sync bots' App-auth block, pinned.
#
#  nvim-sync, starship-sync and theme-sync carry the SAME auth preamble: mint a
#  repo-scoped fleet-App token (#268), then say so out loud when the mint came
#  back empty (#269). Three hand-maintained copies of one block, and until this
#  file nothing read them — no Pester suite opened a sync workflow and the repo
#  has no actionlint/yamllint gate, so a fix applied to two of three would have
#  shipped green. Not hypothetical: the silent degrade this block exists to
#  announce ran for most of a day and was caught by a DIFFERENT repo's weekly
#  sweep, not by this one.
#
#  Text assertions, like RunnerContract.Tests.ps1's over ci.yml — the point is the
#  literal YAML, not a parsed model of it (this suite runs where no YAML parser is
#  a given).
# ============================================================================

# Top level, NOT in BeforeAll: Pester evaluates `-ForEach` during DISCOVERY, which
# runs before any BeforeAll body. A $script: variable set there would be $null here.
$Bots = 'nvim-sync', 'starship-sync', 'theme-sync'

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Wf = @{}
    foreach ($bot in 'nvim-sync', 'starship-sync', 'theme-sync') {
        $script:Wf[$bot] = Get-Content (Join-Path $RepoRoot ".github/workflows/$bot.yml") -Raw
    }

    # The warn block, lifted verbatim: from its leading comment through to the line
    # before the next step at the same indent. Comparing the EXTRACTS is what makes
    # "identical in all three" a fact rather than an intention.
    function Get-WarnBlock {
        param([Parameter(Mandatory)][string]$Yaml)
        $lines = $Yaml -split "`n"
        $hit = $lines | Select-String -SimpleMatch '# #268 stopped one step short' | Select-Object -First 1
        if (-not $hit) { return $null }
        $first = $hit.LineNumber - 1                  # LineNumber is 1-based; $first is the 0-based comment line
        $last = -1
        for ($i = $first + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^      - uses: ') { $last = $i - 1; break }
        }
        if ($last -lt $first) { return $null }
        ($lines[$first..$last]) -join "`n"
    }
}

Describe 'the fleet-App mint is still the thing being guarded' {
    It '<_> mints a scoped token that is allowed to fail' -ForEach $Bots {
        # The precondition for #269: continue-on-error is what turns a failed mint into
        # a green run, and is therefore what makes the warning below necessary. It is
        # also what keeps the warn step REACHABLE on the failure path — a failed step
        # without it fails the job, and a bare `if:` implicitly ANDs success() — so the
        # two have to move together.
        $script:Wf[$_] | Should -Match 'id: app'
        $script:Wf[$_] | Should -Match 'continue-on-error: true'
        $script:Wf[$_] | Should -Match 'create-github-app-token@'
    }
    It '<_> falls back to github.token for both the checkout and the PR' -ForEach $Bots {
        # The two consumers the warning is ABOUT. `|| github.token` is also the standing
        # proof that an unset output is falsy in both branches — the same evaluation the
        # warn step's `if:` relies on.
        ([regex]::Matches($script:Wf[$_], [regex]::Escape('steps.app.outputs.token || github.token'))).Count |
            Should -Be 2
    }
}

Describe 'a degraded run announces itself (#269)' {
    It '<_> gates on the TOKEN being empty' -ForEach $Bots {
        # The one test that covers BOTH branches: a skipped step and a
        # continue-on-error failure leave outputs empty for the same reason.
        $script:Wf[$_] | Should -Match ([regex]::Escape("if: steps.app.outputs.token == ''"))
    }
    It '<_> does not gate on outcome or conclusion' -ForEach $Bots {
        # `outcome == 'failure'` misses the SKIP; `conclusion` is 'success' in both,
        # which is the useless signal. Either substituted for the token test would
        # restore exactly the blind spot #269 closed. (`outcome` may still be READ — the
        # step passes it through env: to name which branch it was — just not gated on.)
        $script:Wf[$_] | Should -Not -Match 'if: steps\.app\.(outcome|conclusion)'
    }
    It '<_> warns AND writes a step summary, naming the consequence' -ForEach $Bots {
        $block = Get-WarnBlock -Yaml $script:Wf[$_]
        $block | Should -Not -BeNullOrEmpty
        $block | Should -Match '::warning::'          # the annotation
        $block | Should -Match 'GITHUB_STEP_SUMMARY'  # and the run's front page
        $block | Should -Match 'BLOCKED'              # the consequence, not just the cause
        $block | Should -Match 'steps\.app\.outcome'  # skipped vs failure, told apart
    }
    # No backticks in a `<_>` name: Pester 5 expands the placeholder by re-parsing the
    # name as an EXPANDABLE string, where a backtick is the escape character — "the `if:`
    # gate" dies with "the string is missing the terminator" before the body ever runs.
    # Pester 6 does not, so this only shows up against the 5.6.1 CI pins.
    It '<_> never lets the token itself out of the if: gate' -ForEach $Bots {
        # The minted token is masked in logs, but $GITHUB_STEP_SUMMARY is rendered
        # markdown and leaning on the masker there is not a bet worth taking. One
        # mention in the whole block, and it is the gate.
        $block = Get-WarnBlock -Yaml $script:Wf[$_]
        ([regex]::Matches($block, 'outputs\.token')).Count | Should -Be 1
    }
    It '<_> warns BEFORE the checkout' -ForEach $Bots {
        # Load-bearing ordering: a bare `if:` implicitly ANDs success(), so placed after
        # checkout a checkout failure would SKIP the warning in the run that most needs
        # the diagnosis. Before it, nothing can have failed yet.
        $lines = $script:Wf[$_] -split "`n"
        $warn = ($lines | Select-String -SimpleMatch '- name: Warn if no App token was minted' |
            Select-Object -First 1).LineNumber
        $checkout = ($lines | Select-String -SimpleMatch '- uses: actions/checkout@' |
            Select-Object -First 1).LineNumber
        $warn | Should -Not -BeNullOrEmpty
        $warn | Should -BeLessThan $checkout
    }
}

Describe 'all three bots carry the SAME block' {
    It 'the warn block is byte-identical across the three workflows' {
        # The whole reason this file exists. Three copies, no linter, no parser: the
        # next person to improve the wording in one bot has to do it in all three.
        # Off $script:Wf, not the discovery-time $Bots — a top-level variable does not
        # survive into an It body, which is the same Pester phase split noted above.
        $blocks = @($script:Wf.Values | ForEach-Object { Get-WarnBlock -Yaml $_ })
        $blocks.Count | Should -Be 3
        ($blocks | Select-Object -Unique).Count | Should -Be 1
    }
}
