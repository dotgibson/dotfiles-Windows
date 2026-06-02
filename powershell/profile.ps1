# ============================================================================
#  profile.ps1  -  entry point, symlinked to $PROFILE by install.ps1
#  dotfiles-Windows :: native host layer for the multi-OS dotfiles fleet
#
#  Loads layers in the same order as the zsh loader on the Linux/Mac repos:
#      core  ->  os (windows)  ->  local
#
#  There is intentionally NO offensive layer here. The offensive role is unique
#  to the Kali station (its own repo, inside WSL). This profile owns the
#  *Windows host* only; WSL distros configure themselves from their own repos.
# ============================================================================

# --- Resolve repo root --------------------------------------------------------
# install.ps1 sets DOTFILES_WIN as a persistent user env var. Fall back to the
# conventional clone location so a freshly-symlinked profile still works.
$DotfilesRoot = $env:DOTFILES_WIN
if (-not $DotfilesRoot) { $DotfilesRoot = Join-Path $HOME 'dotfiles-Windows' }
$global:DOTFILES = $DotfilesRoot
$ProfileDir = Join-Path $DotfilesRoot 'powershell'

# --- Layer loader -------------------------------------------------------------
# Each layer is a directory of NN-name.ps1 fragments, dot-sourced in name order.
foreach ($layer in @('core', 'os')) {
    $dir = Join-Path $ProfileDir $layer
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter '*.ps1' -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object {
                try   { . $_.FullName }
                catch { Write-Warning "dotfiles: failed to load $($_.Name): $_" }
            }
    }
}

# --- Local, machine-specific overrides (gitignored) ---------------------------
$LocalProfile = Join-Path $ProfileDir 'local.ps1'
if (Test-Path $LocalProfile) { . $LocalProfile }
