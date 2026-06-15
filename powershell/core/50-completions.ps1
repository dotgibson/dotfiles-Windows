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
