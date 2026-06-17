# ============================================================================
#  core/50-completions.ps1  -  tab-completion for the repo's own verbs.
#
#  PowerShell already completes DECLARED switches/parameters on advanced
#  functions (e.g. `up -<Tab>` -> -y, `psmux-pill-enable -<Tab>` -> -AllNetworks),
#  so this fragment only adds the ARGUMENT-VALUE completions it can't infer:
#  live psmux session names, installed WSL distros, and the maint-log mode.
#
#  Register-ArgumentCompleter stores completers by command NAME, so it's fine
#  that some of those commands are defined later (os/* layer) — the completer
#  resolves at <Tab> time. Each scriptblock is guarded so it no-ops when the
#  underlying tool isn't installed; nothing here shells out at load.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: (none)
# requires: Get-DotHelpFilters

# Small helper: turn a list of strings into prefix-filtered CompletionResults.
function script:New-DotCompletions {
    param([string[]]$Values, [string]$Word, [string]$Tooltip = '')
    $Values |
        Where-Object { $_ -and $_ -like "$Word*" } |
        Sort-Object -Unique |
        ForEach-Object {
            $tip = if ($Tooltip) { $Tooltip } else { $_ }
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $tip)
        }
}

# --- managed-package sources (read the repo manifests, never shell out) -------
# Completing `sci`/`wgi` from the apps THIS repo manages is the useful, instant
# answer: no `scoop search` subprocess, and it nudges you toward the curated set.
# Guarded + cached-free: returns @() when the manifest isn't resolvable.
function script:Get-DotManagedScoopApps {
    $f = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'packages\scoopfile.json' } else { $null }
    if (-not $f -or -not (Test-Path $f)) { return @() }
    try { @((Get-Content $f -Raw | ConvertFrom-Json).apps.Name) | Where-Object { $_ } } catch { @() }
}
function script:Get-DotManagedWingetIds {
    $f = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'packages\winget.json' } else { $null }
    if (-not $f -or -not (Test-Path $f)) { return @() }
    # Entries may be a bare id string OR a pinned object { id, version } (see B2 /
    # ConvertTo-DotWingetSpec). Normalize to id STRINGS so the completer never tries
    # to build a CompletionResult from a PSCustomObject.
    try {
        @((Get-Content $f -Raw | ConvertFrom-Json).packages) |
            ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_) { "$($_.id)" } } |
            Where-Object { $_ }
    } catch { @() }
}

# sci <app> : scoop apps this repo manages (packages/scoopfile.json)
Register-ArgumentCompleter -CommandName sci -ParameterName App -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    New-DotCompletions -Values (Get-DotManagedScoopApps) -Word $wordToComplete -Tooltip 'scoop app (managed by this repo)'
}

# wgi <id> : winget ids this repo manages (packages/winget.json)
Register-ArgumentCompleter -CommandName wgi -ParameterName id -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    New-DotCompletions -Values (Get-DotManagedWingetIds) -Word $wordToComplete -Tooltip 'winget id (managed by this repo)'
}

# --- mux <session> : existing psmux sessions (attach-or-create) ---------------
Register-ArgumentCompleter -CommandName mux -ParameterName Session -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) { return }
    $sessions = psmux list-sessions -F '#S' 2>$null | Where-Object { $_ -and $_ -notmatch '^_popup_' }
    New-DotCompletions -Values $sessions -Word $wordToComplete -Tooltip 'psmux session'
}

# --- cdwsl -Distro : installed WSL distros ------------------------------------
Register-ArgumentCompleter -CommandName cdwsl -ParameterName Distro -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return }
    # `wsl --list --quiet` is UTF-16; normalize and drop blank lines.
    $distros = (wsl --list --quiet 2>$null) -split "`r?`n" |
        ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }
    New-DotCompletions -Values $distros -Word $wordToComplete -Tooltip 'WSL distro'
}

# --- maint-log [N|-f] : suggest the follow flag -------------------------------
Register-ArgumentCompleter -CommandName maint-log -ParameterName Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    @(
        [System.Management.Automation.CompletionResult]::new('-f', '-f', 'ParameterValue', 'follow the log (tail -f)')
        [System.Management.Automation.CompletionResult]::new('50', '50', 'ParameterValue', 'last N lines')
    ) | Where-Object { $_.CompletionText -like "$wordToComplete*" }
}

# --- dothelp <filter> : the group names + command verbs in the catalog --------
# So `dothelp g<Tab>` offers git / gs / gco / glow…, turning the help index into
# a discoverable, tab-completable surface. Candidates come from the pure
# Get-DotHelpFilters (core/55-help.ps1), resolved lazily at <Tab> time.
Register-ArgumentCompleter -CommandName dothelp -ParameterName Filter -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if (-not (Get-Command Get-DotHelpFilters -ErrorAction SilentlyContinue)) { return }
    New-DotCompletions -Values (Get-DotHelpFilters) -Word $wordToComplete -Tooltip 'dothelp filter'
}
