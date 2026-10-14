# Shared list of managed PowerShell modules.
# Dot-sourced by Install-Packages.ps1 (initial install) and maint/Maintenance.ps1
# (ongoing updates) so both always operate on the same set.
#
# The pins are EXACT, reproducible versions, not a floor: Install-Packages.ps1
# installs precisely these with -RequiredVersion, so a fresh box bootstrapped
# today and one bootstrapped next month land on the identical baseline. The daily
# maintenance runner then rolls each module forward to the latest (that's its
# job) — so a machine is reproducible at install time and current thereafter.
# Bumping a baseline is a one-line, reviewable change here; both consumers pick
# it up automatically. Each value MUST stay an exact x.y[.z] version — the
# dependency-free validator (tests/Invoke-Validation.ps1) gates against a floor
# or range sneaking back in.
#
# One exception to "installs precisely these": a module the host already ships
# in-box ($PSHOME\Modules) at or above its pin is skipped, so the pin acts as the
# floor the host must meet (#286). That only ever applies to PSReadLine today.
#
# To add a module: add one line here (exact version).
# PSReadLine MUST stay >= 2.2.0: that's the first release with bracketed-paste
# support, which is what makes a multi-line paste land as literal text under our
# `Set-PSReadLineOption -EditMode Vi` (core/10-tools.ps1). Below 2.2.0, Vi mode
# interprets a pasted block keystroke-by-keystroke (`:`/`d`/`i`/`Esc` act as Vi
# commands), so paste "switches modes / reorganizes text / runs vim commands".
# The same minimum is asserted by tests/Repo.Tests.ps1.
#
# What this pin can and cannot do for PSReadLine: the console host imports its own
# copy (in-box, or Documents\PowerShell\Modules) BEFORE any profile runs, and a
# second copy — older or newer — fails to import next to it, so core/10-tools.ps1
# never imports over a loaded PSReadLine (#286). The local copy therefore only
# serves hosts that do not preload one. Every supported pwsh ships >= 2.3.4 in-box;
# raising a stale host copy means `Install-Module PSReadLine -Scope CurrentUser`
# (on the default path the host reads), not a change here. 2.4.5 is the current
# gallery release, matching what pwsh 7.6 ships.
$script:MaintModulePins = [ordered]@{
    PSReadLine          = '2.4.5'
    'Terminal-Icons'    = '0.10.0'
    PSFzf               = '2.4.0'
    CompletionPredictor = '0.1.0'
}

# Back-compat / convenience: the bare name list the maint runner iterates.
$script:MaintModuleNames = @($script:MaintModulePins.Keys)
