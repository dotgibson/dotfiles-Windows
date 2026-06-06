# Shared list of managed PowerShell modules.
# Dot-sourced by Install-Packages.ps1 (initial install) and maint/Maintenance.ps1
# (ongoing updates) so both always operate on the same set.
#
# To add a module: add it here only — both scripts pick it up automatically.
$script:MaintModuleNames = @(
    'PSReadLine'
    'Terminal-Icons'
    'PSFzf'
    'CompletionPredictor'
)
