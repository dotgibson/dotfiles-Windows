@{
    # PSScriptAnalyzer settings for dotfiles-Windows.
    # Severity gate is set in CI; this file tunes which rules apply.
    #
    # A few default rules are intentionally excluded because they fight the
    # deliberate design of an interactive shell-profile repo:
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Write-Host is the point here: this repo is all human-facing terminal
        # output with colour, not a pipeline-producing module.
        'PSAvoidUsingWriteHost',

        # The profile layers deliberately publish state via $global: scope
        # (DOTFILES, DotfilesInit, PsmuxPillTimer, ...) so reloads and cross-pane
        # cooperation work. That is by design, not an accident.
        'PSAvoidGlobalVars',

        # Short, muscle-memory verbs (ls, gs, up, mux, ...) are the explicit goal
        # of an aliases layer; the unapproved-verb / singular-noun rules are about
        # shippable modules, not a personal shell.
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',

        # local.ps1 / .gitconfig.local pattern intentionally references files that
        # do not exist in the repo.
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
