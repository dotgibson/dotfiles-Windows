#requires -Version 7
# ============================================================================
#  task.ps1  -  the fleet's `make` verbs, spelled for a host without make.
#
#      .\task.ps1                 the discoverable index of verbs (same as `help`)
#      .\task.ps1 help
#      .\task.ps1 lint            reproduce the CI gate locally
#      .\task.ps1 check           lint, plus the links-only bootstrap previewed
#      .\task.ps1 dry-run         preview a full install, touching nothing
#      .\task.ps1 packages-check  resolve every managed package against scoop/winget
#      .\task.ps1 core-verify     the mirrored Core assets against their recorded ref
#      .\task.ps1 test            the Pester suite, with its coverage gate
#      .\task.ps1 test -NoGate    anything after the verb goes to the script it runs
#
#  Why this exists: dotfiles-core declares ONE set of `make` verbs every repo in the
#  fleet answers to (scripts/make-vocabulary.txt there, dotfiles-core#691), so a
#  contributor moving between repos re-learns nothing. This repo was the exception:
#  no Makefile, no runner, only bare scripts -- in the fleet's most-tested repo, where
#  "reproduce the CI gate locally" has the most to offer (dotfiles-core#855). `make`
#  is not a given on a Windows host and `just` would be a new dependency, so the
#  verbs are spelled in the language the repo is already written in.
#
#  This is a DISPATCHER, not a second implementation. Every verb runs entry points
#  that already exist (tests/Invoke-Validation.ps1, install.ps1, tests/Invoke-Tests.ps1,
#  ...) in a child pwsh with the arguments CI hands them, so "passes here" and "passes
#  CI" stay one assertion, and a step that calls `exit` ends its own process, not the
#  dispatcher's. The first failing step stops the verb and its exit code is yours.
#
#  The verb table is the contract, and it is read STATICALLY by Core's register:
#  scripts/fleet-vocabulary.sh (in dotfiles-core) reads the quoted keys of
#  Get-TaskVerbs below the way it reads a Makefile's rules, and credits `test` only
#  when its Steps name tests/Invoke-Tests.ps1 by path -- that is how the register tells
#  a verb that runs the suite from a stub. So: one quoted key per line, alone at the
#  start of its line, and the suite named by path. tests/Task.Tests.ps1 pins both.
#
#  Pure helpers are exposed for unit tests via DOTFILES_TASK_LIBONLY=1 (the same
#  library-only hook every other script here uses).
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Verb = 'help',
    # Everything after the verb, handed untouched to the script the verb runs.
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'

# --- Get-TaskVerbs ------------------------------------------------------------
# THE VERB TABLE. Keys are the fleet's canonical names, in the contract's order;
# Meaning is what `help` prints; Steps are the entry points the verb runs, in order,
# each as `<script relative to the repo root> [args]` (paths carry no spaces here).
# A verb with ONE step passes the caller's extra arguments to it; a multi-step verb
# takes none, because there is no honest way to say which step they were for.
function Get-TaskVerbs {
    [ordered]@{
        'help'           = @{
            Meaning = 'the discoverable index of verbs (this)'
            Steps   = @()
        }
        'lint'           = @{
            Meaning = 'reproduce the CI gate locally: syntax, manifests, editorconfig, generated theme blocks'
            # The two dependency-free Linux legs of ci.yml, in its order. PSScriptAnalyzer
            # rides inside Invoke-Validation.ps1 when it is installed (tests/Install-DevDeps.ps1).
            Steps   = @(
                'tests/Invoke-Validation.ps1'
                'gen-theme.ps1 -Check'
            )
        }
        'check'          = @{
            Meaning = 'lint, plus the links-only bootstrap -- previewed, since Windows has no throwaway HOME to run it in'
            Steps   = @(
                'tests/Invoke-Validation.ps1'
                'gen-theme.ps1 -Check'
                'install.ps1 -SkipPackages -DryRun -NonInteractive'
            )
        }
        'dry-run'        = @{
            Meaning = 'preview a full install (packages + symlinks), touching nothing'
            Steps   = @(
                'install.ps1 -DryRun -NonInteractive'
            )
        }
        'packages-check' = @{
            Meaning = 'resolve every managed scoop/winget package against its manager (what package-freshness.yml runs)'
            Steps   = @(
                'packages/Check-PackageFreshness.ps1'
            )
        }
        'core-verify'    = @{
            Meaning = 'the three assets mirrored from dotfiles-core (nvim/, starship, theme) against their recorded .core-ref'
            Steps   = @(
                'tests/Assert-NvimParity.ps1'
                'tests/Assert-StarshipParity.ps1'
                'tests/Assert-ThemeParity.ps1'
            )
        }
        'test'           = @{
            Meaning = 'the Pester suite with its coverage gate, exactly as CI runs it'
            Steps   = @(
                'tests/Invoke-Tests.ps1'
            )
        }
    }
}

# --- Get-TaskHelpText ---------------------------------------------------------
# The `help` verb's lines, pure so the suite can assert on them without a spawn.
function Get-TaskHelpText {
    $verbs = Get-TaskVerbs
    $width = ($verbs.Keys | Measure-Object -Maximum -Property Length).Maximum
    @(
        'dotfiles-Windows -- task.ps1 verbs (the fleet make vocabulary, dotfiles-core#691):'
        ''
    ) + @(
        foreach ($name in $verbs.Keys) {
            '  {0}  {1}' -f $name.PadRight($width), $verbs[$name].Meaning
        }
    ) + @(
        ''
        'Anything after a single-step verb is passed to the script it runs:'
        '  .\task.ps1 test -NoGate      .\task.ps1 dry-run -SkipPackages'
        'The same verbs mean the same things in every repo of the fleet; see'
        'scripts/make-vocabulary.txt in dotfiles-core.'
    )
}

# Library-only hook: tests dot-source the table and help text without dispatching.
if ($env:DOTFILES_TASK_LIBONLY -eq '1') { return }

$verbs = Get-TaskVerbs
if (-not $verbs.Contains($Verb)) {
    Write-Host "task.ps1: unknown verb '$Verb'" -ForegroundColor Red
    Get-TaskHelpText | ForEach-Object { Write-Host $_ }
    exit 2
}

if ($Verb -eq 'help') {
    Get-TaskHelpText | ForEach-Object { Write-Host $_ }
    exit 0
}

$steps = @($verbs[$Verb].Steps)
if ($Rest.Count -and $steps.Count -ne 1) {
    Write-Host "task.ps1: '$Verb' runs $($steps.Count) scripts and takes no arguments of its own (got: $($Rest -join ' '))" -ForegroundColor Red
    exit 2
}

# The pwsh running this script, so a box with several PowerShells runs the steps in
# the one the contributor chose. -File so a step's `exit N` is its own process ending,
# reported back through $LASTEXITCODE; -ExecutionPolicy Bypass (process-scoped) as the
# pre-commit hook does, so a restrictive policy cannot block trusted in-repo scripts.
$pwsh = (Get-Process -Id $PID).Path
# A step's non-zero exit is reported below with the verb and script named, not thrown
# as a NativeCommandExitException by a host that opted into that preference.
$PSNativeCommandUseErrorActionPreference = $false
foreach ($step in $steps) {
    $parts    = $step -split '\s+'
    $path     = Join-Path $PSScriptRoot $parts[0]
    $stepArgs = @($parts | Select-Object -Skip 1)
    if ($steps.Count -eq 1) { $stepArgs += $Rest }
    Write-Host ("task.ps1 {0}: {1} {2}" -f $Verb, $parts[0], ($stepArgs -join ' ')).TrimEnd() -ForegroundColor Cyan
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File $path @stepArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("task.ps1 {0}: {1} exited {2}" -f $Verb, $parts[0], $LASTEXITCODE) -ForegroundColor Red
        exit $LASTEXITCODE
    }
}
exit 0
