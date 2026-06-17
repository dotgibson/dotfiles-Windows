# ============================================================================
#  Dotfiles/Modules.Helpers.ps1  -  pure logic for the local module dir (B11).
#
#  modules-localize copies the managed PowerShell modules onto fast local disk
#  (off OneDrive). Over time the local dir ACCUMULATES: the maintenance runner
#  rolls a module forward (installing a newer version beside the old one) and the
#  copy step never reaps the leftover, so a box ends up carrying several versions
#  of PSReadLine et al. Get-DotModulePrunePlan decides which version directories
#  are redundant, so the reconcile is pure and unit-tested; the actual Remove-Item
#  lives at the call site in os/30-windows.ps1.
#
#  Imported by the Dotfiles module (exported as Get-DotModulePrunePlan) and
#  side-effect-free on load.
# ============================================================================

# --- Get-DotModulePrunePlan ---------------------------------------------------
# Given the installed module/version directories and the MANAGED module names,
# return the entries to remove: for each managed module with more than one
# parseable version, keep the highest and mark the rest. Deliberately conservative:
#   • only managed modules are touched — a user's own side-loaded modules and any
#     non-managed leftovers are left completely alone;
#   • a version string that isn't a clean [version] (e.g. a prerelease tag) is
#     never pruned — we won't guess an ordering and risk deleting the wrong one;
#   • a module with a single version is left as-is.
# $Installed items are pscustomobjects with Name / Version / Path; the SAME
# objects (carrying Path) come back, so the caller just deletes $_.Path.
function Get-DotModulePrunePlan {
    param(
        [object[]]$Installed,
        [string[]]$ManagedNames
    )
    $managed = @($ManagedNames | Where-Object { $_ })
    $remove = [System.Collections.Generic.List[object]]::new()
    if (-not $Installed -or -not $managed) { return @($remove) }

    foreach ($grp in @($Installed | Where-Object { $managed -contains $_.Name } | Group-Object Name)) {
        # Pair each entry with its parsed [version]; unparseable versions drop out
        # here and are therefore never candidates for removal.
        $parsed = foreach ($m in $grp.Group) {
            $v = $null
            if ([version]::TryParse([string]$m.Version, [ref]$v)) {
                [pscustomobject]@{ Item = $m; Ver = $v }
            }
        }
        $parsed = @($parsed)
        if ($parsed.Count -lt 2) { continue }   # 0/1 comparable version -> nothing stale
        $max = ($parsed | Sort-Object Ver -Descending | Select-Object -First 1).Ver
        foreach ($p in $parsed) {
            if ($p.Ver -lt $max) { $remove.Add($p.Item) }
        }
    }
    @($remove)
}
