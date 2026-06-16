# Shared list of managed PowerShell modules.
# Dot-sourced by Install-Packages.ps1 (initial install) and maint/Maintenance.ps1
# (ongoing updates) so both always operate on the same set.
#
# The pins are a reproducibility FLOOR, not a freeze: Install-Packages.ps1 uses
# -MinimumVersion so a fresh box lands on a known-good baseline, while the daily
# maintenance runner keeps pulling the latest (that's its job). Bumping a floor
# is a one-line, reviewable change here — both consumers pick it up automatically.
#
# To add a module: add one line here.
$script:MaintModulePins = [ordered]@{
    PSReadLine          = '2.2.0'
    'Terminal-Icons'    = '0.10.0'
    PSFzf               = '2.4.0'
    CompletionPredictor = '0.1.0'
}

# Back-compat / convenience: the bare name list the maint runner iterates.
$script:MaintModuleNames = @($script:MaintModulePins.Keys)
