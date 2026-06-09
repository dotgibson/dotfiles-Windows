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

# --- UTF-8 I/O ----------------------------------------------------------------
# Force UTF-8 in/out so the Nerd Font glyphs from starship, eza, bat, and psmux
# render regardless of the console's legacy codepage (some hosts still start on
# 437/1252). Cheap, and runs before anything prints. Guarded so a host that
# rejects the assignment (rare) can't abort profile load.
try {
    [Console]::OutputEncoding = [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

# --- Modules off OneDrive -----------------------------------------------------
# When Documents is redirected to OneDrive, the default CurrentUser module path
# (Documents\PowerShell\Modules) is OneDrive-synced — and importing modules from
# there taxes EVERY shell start with placeholder hydration / sync I/O (seconds).
# Prepend a local, non-synced modules dir so imports resolve from fast local disk
# first. Populate it once with `modules-localize` (os/30-windows.ps1); the
# installer and maintenance runner keep managed modules here going forward.
$LocalModules = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
if ($env:PSModulePath -notlike "*$LocalModules*") {
    $env:PSModulePath = $LocalModules + [System.IO.Path]::PathSeparator + $env:PSModulePath
}

# --- Optional load tracer -----------------------------------------------------
# Set DOTFILES_PROFILE_TRACE=1 in the ENVIRONMENT before pwsh starts to time each
# fragment (and the heavier steps inside 10-tools, which record via Add-DotfilesTrace).
# A sorted table prints at the end of load so you can see exactly where the time
# goes. Must be an env var (read before the profile runs); a lean way to check:
#   $env:DOTFILES_PROFILE_TRACE='1'; pwsh -NoLogo   # child inherits it, prints the table
$global:DotfilesTraceOn = ($env:DOTFILES_PROFILE_TRACE -eq '1')
$global:DotfilesTrace   = if ($global:DotfilesTraceOn) { [System.Collections.Generic.List[object]]::new() } else { $null }
function global:Add-DotfilesTrace {
    param([string]$Step, [double]$Ms)
    if ($global:DotfilesTrace) { $global:DotfilesTrace.Add([pscustomobject]@{ Step = $Step; ms = [int]$Ms }) }
}

# --- Layer loader -------------------------------------------------------------
# Each layer is a directory of NN-name.ps1 fragments, dot-sourced in name order.
foreach ($layer in @('core', 'os')) {
    $dir = Join-Path $ProfileDir $layer
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter '*.ps1' -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object {
                $fragment = $_
                if ($global:DotfilesTraceOn) { $__sw = [System.Diagnostics.Stopwatch]::StartNew() }
                try   { . $fragment.FullName }
                catch { Write-Warning "dotfiles: failed to load $($fragment.Name): $_" }
                if ($global:DotfilesTraceOn) {
                    $__sw.Stop()
                    Add-DotfilesTrace "fragment $layer/$($fragment.Name)" $__sw.Elapsed.TotalMilliseconds
                }
            }
    }
}

# --- Local, machine-specific overrides (gitignored) ---------------------------
$LocalProfile = Join-Path $ProfileDir 'local.ps1'
if (Test-Path $LocalProfile) { . $LocalProfile }

# --- Emit the trace table (if tracing) ----------------------------------------
if ($global:DotfilesTraceOn -and $global:DotfilesTrace.Count) {
    Write-Host "`nprofile load trace (slowest first):" -ForegroundColor Cyan
    $global:DotfilesTrace | Sort-Object ms -Descending | Format-Table -AutoSize | Out-Host
}
