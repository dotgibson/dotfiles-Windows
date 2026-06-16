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
$script:MaintModulePins = [ordered]@{
    PSReadLine          = '2.2.0'
    'Terminal-Icons'    = '0.10.0'
    PSFzf               = '2.4.0'
    CompletionPredictor = '0.1.0'
}

# Back-compat / convenience: the bare name list the maint runner iterates.
$script:MaintModuleNames = @($script:MaintModulePins.Keys)
