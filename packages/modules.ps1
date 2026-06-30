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
# To add a module: add one line here (exact version).
# PSReadLine MUST stay >= 2.2.0: that's the first release with bracketed-paste
# support, which is what makes a multi-line paste land as literal text under our
# `Set-PSReadLineOption -EditMode Vi` (core/10-tools.ps1). Below 2.2.0, Vi mode
# interprets a pasted block keystroke-by-keystroke (`:`/`d`/`i`/`Esc` act as Vi
# commands), so paste "switches modes / reorganizes text / runs vim commands".
# 2.3.6 is the current gallery release; the in-box PSReadLine on some hosts still
# predates 2.2.0, so pinning a recent version here is the fix. The same minimum
# is asserted by tests/Repo.Tests.ps1.
$script:MaintModulePins = [ordered]@{
    PSReadLine          = '2.3.6'
    'Terminal-Icons'    = '0.10.0'
    PSFzf               = '2.4.0'
    CompletionPredictor = '0.1.0'
}

# Back-compat / convenience: the bare name list the maint runner iterates.
$script:MaintModuleNames = @($script:MaintModulePins.Keys)
