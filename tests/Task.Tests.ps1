# ============================================================================
#  tests/Task.Tests.ps1  -  task.ps1 speaks the fleet's make vocabulary.
#
#  dotfiles-core declares the seven canonical `make` verbs once
#  (scripts/make-vocabulary.txt, dotfiles-core#691) and its register reads this repo's
#  task.ps1 STATICALLY -- the quoted keys of Get-TaskVerbs, and whether `test`'s steps
#  name tests/Invoke-Tests.ps1 by path (dotfiles-core#855). These pin the three facts
#  that contract rests on: the verb set is exactly the fleet's, in its order; every
#  step names a script that exists; and the table keeps the shape the register reads.
# ============================================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:TaskPath = Join-Path $script:RepoRoot 'task.ps1'
    $env:DOTFILES_TASK_LIBONLY = '1'
    . $script:TaskPath
    $script:Verbs = Get-TaskVerbs
    $script:TaskText = Get-Content $script:TaskPath -Raw
    # The contract, in the contract's order (scripts/make-vocabulary.txt in Core).
    $script:Canonical = @('help', 'lint', 'check', 'dry-run', 'packages-check', 'core-verify', 'test')
}
AfterAll { Remove-Item Env:DOTFILES_TASK_LIBONLY -ErrorAction SilentlyContinue }

Describe 'task.ps1 verb table (the fleet make vocabulary)' {
    It 'declares exactly the seven canonical verbs, in the contract order' {
        (@($script:Verbs.Keys) -join ' ') | Should -Be ($script:Canonical -join ' ') `
            -Because 'scripts/make-vocabulary.txt in dotfiles-core is the contract; a verb spelled differently here is a missing register cell'
    }

    It 'gives every verb a meaning for help to print' {
        foreach ($name in $script:Verbs.Keys) {
            $script:Verbs[$name].Meaning | Should -Not -BeNullOrEmpty -Because "'$name' has no Meaning"
        }
    }

    It 'names only scripts that exist, relative to the repo root' {
        foreach ($name in $script:Verbs.Keys) {
            foreach ($step in @($script:Verbs[$name].Steps)) {
                $rel = ($step -split '\s+')[0]
                (Join-Path $script:RepoRoot $rel) | Should -Exist -Because "'$name' runs '$rel', which is not in the repo"
            }
        }
    }

    It 'help is the only verb with no steps, and every other verb has at least one' {
        @($script:Verbs['help'].Steps).Count | Should -Be 0
        foreach ($name in ($script:Verbs.Keys | Where-Object { $_ -ne 'help' })) {
            @($script:Verbs[$name].Steps).Count | Should -BeGreaterThan 0 -Because "'$name' would be a stub, and the fleet has no stub form for a verb that applies here"
        }
    }

    It 'test runs tests/Invoke-Tests.ps1, the one way to run the suite, by path' {
        # The register credits `test` only when its steps name the suite runner; a
        # `test` routed through anything else reads as **no-op** in Core's register.
        @($script:Verbs['test'].Steps) | Should -Contain 'tests/Invoke-Tests.ps1'
    }

    It 'lint runs the dependency-free CI legs (Invoke-Validation, gen-theme -Check)' {
        @($script:Verbs['lint'].Steps) | Should -Contain 'tests/Invoke-Validation.ps1'
        @($script:Verbs['lint'].Steps) | Should -Contain 'gen-theme.ps1 -Check'
    }

    It 'check is lint plus the links-only bootstrap, previewed' {
        $lint  = @($script:Verbs['lint'].Steps)
        $check = @($script:Verbs['check'].Steps)
        ($check[0..($lint.Count - 1)] -join ' ; ') | Should -Be ($lint -join ' ; ') -Because 'check must begin with exactly what lint runs'
        $check[-1] | Should -Match '^install\.ps1 .*-SkipPackages' -Because 'the links-only run is install.ps1 without packages'
        $check[-1] | Should -Match '-DryRun' -Because 'Windows has no throwaway HOME, so the run is previewed, never applied'
    }

    It 'core-verify asserts all three mirrored assets against their .core-ref' {
        $steps = @($script:Verbs['core-verify'].Steps)
        foreach ($gate in 'Nvim', 'Starship', 'Theme') {
            $steps | Should -Contain "tests/Assert-${gate}Parity.ps1"
        }
    }
}

Describe 'task.ps1 keeps the shape the Core register reads' {
    It 'declares each verb as a quoted key alone at the start of its line' {
        # scripts/fleet-vocabulary.sh (dotfiles-core) reads `'<verb>' = @{` at line start.
        foreach ($name in $script:Canonical) {
            $script:TaskText | Should -Match "(?m)^\s*'$([regex]::Escape($name))'\s*=\s*@\{" `
                -Because "'$name' is not declared in the one-key-per-line shape the register greps"
        }
    }

    It 'names the suite runner inside the test entry, on a non-comment line' {
        $m = [regex]::Match($script:TaskText, "(?ms)^\s*'test'\s*=\s*@\{(.*?)^\s*\}")
        $m.Success | Should -BeTrue
        $named = $m.Groups[1].Value -split "`n" |
            Where-Object { $_.TrimStart() -notlike '#*' -and $_ -match 'tests[/\\]Invoke-Tests\.ps1' }
        $named | Should -Not -BeNullOrEmpty -Because 'the register credits test only when the runner is named by path in its entry'
    }

    It 'exposes the library-only hook like every other script here' {
        $script:TaskText | Should -Match 'DOTFILES_TASK_LIBONLY'
    }
}

Describe 'task.ps1 help text' {
    It 'lists every verb with its meaning' {
        $text = (Get-TaskHelpText) -join "`n"
        foreach ($name in $script:Canonical) {
            $text | Should -Match "(?m)^\s+$([regex]::Escape($name))\s+\S" -Because "help does not list '$name'"
            $text | Should -BeLike "*$($script:Verbs[$name].Meaning)*"
        }
    }

    It 'points at the contract it implements' {
        (Get-TaskHelpText) -join "`n" | Should -Match 'make-vocabulary\.txt'
    }
}

Describe 'task.ps1 dispatch (child pwsh)' {
    BeforeAll {
        # The spawned dispatcher must not inherit the library-only hook, or it returns
        # before dispatching and every verb "succeeds".
        $script:Pwsh = (Get-Process -Id $PID).Path
        $script:SavedHook = $env:DOTFILES_TASK_LIBONLY
        Remove-Item Env:DOTFILES_TASK_LIBONLY -ErrorAction SilentlyContinue
    }
    AfterAll { $env:DOTFILES_TASK_LIBONLY = $script:SavedHook }

    It 'with no verb prints help and exits 0' {
        $out = & $script:Pwsh -NoProfile -File $script:TaskPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        foreach ($name in $script:Canonical) { $out | Should -Match "(?m)^\s+$([regex]::Escape($name))\s" }
    }

    It 'help exits 0' {
        $null = & $script:Pwsh -NoProfile -File $script:TaskPath help 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'an unknown verb names itself, prints the index, and exits 2' {
        $out = & $script:Pwsh -NoProfile -File $script:TaskPath no-such-verb 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 2
        $out | Should -Match "unknown verb 'no-such-verb'"
        $out | Should -Match '(?m)^\s+dry-run\s'
    }

    It 'a multi-step verb refuses pass-through arguments rather than guessing a recipient' {
        $out = & $script:Pwsh -NoProfile -File $script:TaskPath lint -Nonsense 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 2
        $out | Should -Match 'takes no arguments'
    }
}
