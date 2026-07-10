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
$pathSep = [System.IO.Path]::PathSeparator
# Compare LITERALLY, and null-safely. `-notlike "*$LocalModules*"` treats the path as a
# WILDCARD pattern, so a %LOCALAPPDATA% containing `[` or `]` (a username like user[1], or a
# redirected profile) would make the guard mis-fire. Use the `-split` OPERATOR (not the
# .Split() METHOD, which THROWS when PSModulePath is unset) so a minimal env with no
# PSModulePath still loads the profile. Path compare is case-insensitive.
if (($env:PSModulePath -split [regex]::Escape($pathSep)) -notcontains $LocalModules) {
    $env:PSModulePath = $LocalModules + $pathSep + $env:PSModulePath
}

# --- Optional load tracer -----------------------------------------------------
# Set DOTFILES_PROFILE_TRACE=1 in the ENVIRONMENT before pwsh starts to time each
# fragment (and the heavier steps inside 10-tools, which record via Add-DotfilesTrace).
# A sorted table prints at the end of load so you can see exactly where the time
# goes. Must be an env var (read before the profile runs); a lean way to check:
#   $env:DOTFILES_PROFILE_TRACE='1'; pwsh -NoLogo   # child inherits it, prints the table
$global:DotfilesTraceOn = ($env:DOTFILES_PROFILE_TRACE -eq '1')
# NB: assign the List directly, NOT via `$x = if (...) { [List]::new() }`. An `if`
# used as an expression emits its value through the pipeline, which enumerates the
# (empty) List to zero items and leaves $global:DotfilesTrace as $null — which would
# silently disable every Add-DotfilesTrace call and suppress the trace table.
if ($global:DotfilesTraceOn) {
    $global:DotfilesTrace = [System.Collections.Generic.List[object]]::new()
} else {
    $global:DotfilesTrace = $null
}
function global:Add-DotfilesTrace {
    param([string]$Step, [double]$Ms)
    # Explicit null check: an EMPTY List is falsy in PowerShell, so `if ($global:DotfilesTrace)`
    # would suppress the very first .Add() and the list would stay empty forever.
    if ($null -ne $global:DotfilesTrace) { $global:DotfilesTrace.Add([pscustomobject]@{ Step = $Step; ms = [int]$Ms }) }
}

# --- Layer loader -------------------------------------------------------------
# Each layer is a directory of NN-name.ps1 fragments, dot-sourced in name order.
# A fragment that throws is logged but never aborts the rest of the load — and
# the failure is RECORDED in $global:DotfilesLoadErrors so it isn't a silent
# mystery: dotfiles-doctor reports it, and a one-line nudge prints below. A clean
# load leaves the list empty.
$global:DotfilesLoadErrors = [System.Collections.Generic.List[string]]::new()

# --- Dotfiles module (B7) -----------------------------------------------------
# The non-interactive helper surface (core/05-lib.ps1) lives in a real module
# now; import it FIRST so its exported helpers exist before any fragment (or
# local.ps1) calls them. The INTERACTIVE layer — tool inits/prompt, PSReadLine
# keybinds, argument completers, CommandNotFoundAction — stays dot-sourced as
# fragments below on purpose (a module-scoped `prompt` is ignored by the host).
# If the import fails we leave 05-lib in the fragment loader (it is NOT skipped
# below), so a broken module degrades to the old dot-source path rather than a
# helperless shell.
$script:DotfilesModuleLoaded = $false
$DotfilesModule = Join-Path $ProfileDir 'Dotfiles/Dotfiles.psd1'
if (Test-Path $DotfilesModule) {
    try {
        Import-Module $DotfilesModule -Force -Global -DisableNameChecking -ErrorAction Stop
        $script:DotfilesModuleLoaded = $true
    } catch {
        # Keep a stable, single-line message in the load-error list and warning —
        # the full ErrorRecord ($_) renders multi-line (CategoryInfo/position) and
        # would make the degraded-load summary unreadable.
        $msg = $_.Exception.Message
        $global:DotfilesLoadErrors.Add("module Dotfiles: $msg")
        Write-Warning "dotfiles: failed to import the Dotfiles module: $msg"
    }
}

foreach ($layer in @('core', 'os')) {
    $dir = Join-Path $ProfileDir $layer
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter '*.ps1' -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object {
                $fragment = $_
                # 05-lib is owned by the Dotfiles module (imported above). Skip it in
                # the loader ONLY when that import succeeded; otherwise fall through
                # and dot-source it here so the shell still gets its helpers.
                if ($script:DotfilesModuleLoaded -and $fragment.Name -eq '05-lib.ps1') { return }
                if ($global:DotfilesTraceOn) { $__sw = [System.Diagnostics.Stopwatch]::StartNew() }
                try   { . $fragment.FullName }
                catch {
                    $global:DotfilesLoadErrors.Add("$layer/$($fragment.Name): $_")
                    Write-Warning "dotfiles: failed to load $($fragment.Name): $_"
                }
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

# --- surface a degraded load (B7) ---------------------------------------------
# If any fragment failed, say so once — a half-loaded profile that looks fine is
# worse than a visible warning. `dotfiles-doctor` has the per-fragment detail.
if ($global:DotfilesLoadErrors.Count -and $env:FAST_START -ne '1') {
    $n = $global:DotfilesLoadErrors.Count
    # Name the fragments that failed (the "<layer>/<file>" prefix recorded before
    # each error message), not just the count, so the nudge is actionable on its own
    # instead of forcing a second `dotfiles-doctor` run just to see WHICH ones (U8).
    $names = $global:DotfilesLoadErrors | ForEach-Object { ($_ -split ':\s', 2)[0] }
    $msg = "dotfiles: $n profile fragment(s) failed to load: $($names -join ', ')"
    # Prefer the shared warning layout, but fall back to Write-Warning: 05-lib could
    # itself be the fragment that failed, in which case Write-DotWarn won't exist.
    if (Get-Command Write-DotWarn -ErrorAction SilentlyContinue) {
        Write-DotWarn $msg 'run dotfiles-doctor for the error detail, then: reload'
    } else {
        Write-Warning "$msg — run dotfiles-doctor for detail."
    }
}

# --- Emit the trace table (if tracing) ----------------------------------------
if ($global:DotfilesTraceOn -and $global:DotfilesTrace.Count) {
    Write-Host "`nprofile load trace (slowest first):" -ForegroundColor Cyan
    $global:DotfilesTrace | Sort-Object ms -Descending | Format-Table -AutoSize | Out-Host
}
