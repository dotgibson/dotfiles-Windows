# ============================================================================
#  install.ps1  -  bootstrap the Windows host
#
#  Usage (from the repo root):
#      .\install.ps1                 # packages + symlinks
#      .\install.ps1 -SkipPackages   # just (re)wire the symlinks
#
#  Symlinks require either Developer Mode (Settings > System > For developers)
#  OR an elevated shell. The script detects this and falls back to copying
#  with a warning if neither is available.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$SkipPackages
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- can we make symlinks? ----------------------------------------------------
function Test-CanSymlink {
    $devMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    return ($devMode -eq 1) -or $isAdmin
}

# --- Test-SymlinkCurrent ------------------------------------------------------
# True only when $Link already exists, IS a symbolic link, and points at $Target.
# This is what makes re-running install.ps1 idempotent: a link that's already
# correct is left untouched instead of being backed up and recreated (which used
# to spawn a fresh `.bak` on every run). Pure/filesystem-only, so it's unit-tested.
function Test-SymlinkCurrent {
    param([string]$Link, [string]$Target)
    if (-not (Test-Path -LiteralPath $Link)) { return $false }
    $item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.LinkType -ne 'SymbolicLink') { return $false }
    $current = @($item.Target)[0]
    if (-not $current) { return $false }
    # Compare resolved absolute paths; fall back to a raw compare if either side
    # can't be resolved (e.g. a dangling link). Case-insensitive to match NTFS.
    try {
        $a = (Resolve-Path -LiteralPath $current -ErrorAction Stop).Path
        $b = (Resolve-Path -LiteralPath $Target  -ErrorAction Stop).Path
    } catch {
        return [string]::Equals($current, $Target, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
}

# --- link helper --------------------------------------------------------------
function Link-Item {
    param([string]$Target, [string]$Link)
    $parent = Split-Path -Parent $Link
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    # Idempotent: a link already pointing where we want needs no work — skip it so
    # repeated runs don't pile up `.bak` files. Only real files, or wrong/stale
    # links, get backed up and replaced.
    if ($CanSymlink -and (Test-SymlinkCurrent -Link $Link -Target $Target)) {
        Write-Host "  ok      $Link (already linked)" -ForegroundColor DarkGray
        return
    }

    if (Test-Path $Link) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Move-Item $Link "$Link.$stamp.bak" -Force
        Write-Host "  backed up existing -> $Link.$stamp.bak" -ForegroundColor DarkYellow
    }
    if ($CanSymlink) {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force | Out-Null
        Write-Host "  linked  $Link" -ForegroundColor Green
    } else {
        # -Recurse so directory targets (nvim\, psmux\scripts) copy in full — a
        # plain Copy-Item only takes the top-level entry and leaves them empty.
        $recurse = (Test-Path $Target -PathType Container)
        Copy-Item $Target $Link -Force -Recurse:$recurse
        Write-Host "  copied  $Link" -ForegroundColor Green
    }
}

# Library-only hook: dot-sourcing with DOTFILES_INSTALL_LIBONLY=1 exposes the
# functions above (for the test suite) without running the bootstrap below.
if ($env:DOTFILES_INSTALL_LIBONLY -eq '1') { return }

# --- preflight: shell version, Mark-of-the-Web, execution policy --------------
# Warn (do not block) if running under Windows PowerShell 5.1. Bootstrapping
# from 5.1 is fine - this run installs pwsh 7 - but the profile is wired for
# pwsh, so daily work should happen there afterward.
if ($PSVersionTable.PSEdition -ne 'Core') {
    Write-Warning 'Running under Windows PowerShell 5.1. This bootstrap works, but do your daily work in PowerShell 7 (pwsh) afterward - the profile targets the pwsh path.'
}

# Strip the "downloaded from the internet" flag off the repo so RemoteSigned
# policy will not block our own scripts. A `git clone` avoids this entirely;
# this matters when the repo arrived as a downloaded archive.
Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# Ensure scripts can run for this user. RemoteSigned is the minimum the profile
# needs to load each session. Leave it alone if Group Policy already pins one.
try {
    $cur = Get-ExecutionPolicy -Scope CurrentUser
    if ($cur -notin 'RemoteSigned','Unrestricted','Bypass') {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host 'Set CurrentUser execution policy to RemoteSigned.' -ForegroundColor DarkGray
    }
} catch {
    Write-Warning "Could not set execution policy (Group Policy may control it): $_"
}

$CanSymlink = Test-CanSymlink
if (-not $CanSymlink) {
    Write-Warning 'Neither Developer Mode nor admin detected. Falling back to COPY (changes will not auto-track the repo).'
    Write-Warning 'For true symlinks: enable Developer Mode, or re-run from an elevated PowerShell.'
}

# --- 1. persistent env var ----------------------------------------------------
Write-Host '== Setting DOTFILES_WIN ==' -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable('DOTFILES_WIN', $RepoRoot, 'User')
$env:DOTFILES_WIN = $RepoRoot

# --- 2. packages --------------------------------------------------------------
if (-not $SkipPackages) {
    Write-Host '== Installing packages ==' -ForegroundColor Cyan
    & (Join-Path $RepoRoot 'packages\Install-Packages.ps1')
}

# --- 3. wire symlinks ---------------------------------------------------------
Write-Host '== Wiring configs ==' -ForegroundColor Cyan

# PowerShell 7 profile. Resolve the Documents folder the OneDrive-aware way:
# [Environment]::GetFolderPath('MyDocuments') follows a OneDrive redirect, so we
# link the profile pwsh ACTUALLY loads. Hardcoding ~\Documents silently links a
# path pwsh never reads when Documents is redirected to OneDrive.
$docs = [Environment]::GetFolderPath('MyDocuments')
$psProfile = Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
Link-Item -Target (Join-Path $RepoRoot 'powershell\profile.ps1') -Link $psProfile
Write-Host "  (profile target: $psProfile)" -ForegroundColor DarkGray

# Neovim
Link-Item -Target (Join-Path $RepoRoot 'nvim') -Link (Join-Path $env:LOCALAPPDATA 'nvim')

# git
Link-Item -Target (Join-Path $RepoRoot 'git\.gitconfig')        -Link (Join-Path $HOME '.gitconfig')
Link-Item -Target (Join-Path $RepoRoot 'git\.gitignore_global') -Link (Join-Path $HOME '.gitignore_global')

# ssh
Link-Item -Target (Join-Path $RepoRoot 'ssh\config') -Link (Join-Path $HOME '.ssh\config')

# psmux (native Windows tmux) — reads ~/.config/psmux/psmux.conf (NOT ~/.tmux.conf).
# Same config psmux/pmux/tmux use. reset.conf + scripts are linked alongside it.
Link-Item -Target (Join-Path $RepoRoot 'psmux\psmux.conf') -Link (Join-Path $HOME '.config\psmux\psmux.conf')
Link-Item -Target (Join-Path $RepoRoot 'psmux\psmux.reset.conf') -Link (Join-Path $HOME '.config\psmux\psmux.reset.conf')
Link-Item -Target (Join-Path $RepoRoot 'psmux\scripts') -Link (Join-Path $HOME '.config\psmux\scripts')

# --- ppm (psmux plugin manager) -------------------------------------------------
# Mirrors psmux's documented install: clone the psmux-plugins monorepo to a temp
# dir, copy ONLY the ppm subfolder into ~/.psmux/plugins/ppm — psmux's standard
# plugin path. That's the same ~/.psmux tree psmux uses for its own runtime files
# (session port/key files, warm session) and where resurrect/continuum write their
# saves, so everything plugin-related lives under one root. The other @plugins
# declared in psmux.conf are fetched later by `prefix + I` inside psmux.
$ppmDir = Join-Path $HOME '.psmux\plugins\ppm'
if (-not (Test-Path $ppmDir)) {
    $tmp = Join-Path $env:TEMP ('psmux-plugins-' + [guid]::NewGuid().ToString('N'))
    try {
        git clone --depth 1 https://github.com/psmux/psmux-plugins.git $tmp
        if ($LASTEXITCODE -eq 0) {
            New-Item -ItemType Directory -Force -Path (Split-Path $ppmDir) | Out-Null
            Copy-Item (Join-Path $tmp 'ppm') $ppmDir -Recurse -Force
            Write-Host "  installed ppm -> $ppmDir" -ForegroundColor Green
        } else {
            Write-Warning 'ppm clone failed — clone psmux-plugins by hand, copy ppm\ to ~\.psmux\plugins\ppm'
        }
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Windows Terminal settings (Store install path)
$wtDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
if (Test-Path $wtDir) {
    Link-Item -Target (Join-Path $RepoRoot 'windows-terminal\settings.json') -Link (Join-Path $wtDir 'settings.json')
} else {
    Write-Warning "Windows Terminal LocalState not found. If you installed WT via scoop, link settings.json manually."
}

# --- 4. .wslconfig (COPY, don't symlink - it's host-global, edit per machine) -
$wslCfg = Join-Path $HOME '.wslconfig'
if (-not (Test-Path $wslCfg)) {
    Copy-Item (Join-Path $RepoRoot 'wsl\windows.wslconfig.example') $wslCfg
    Write-Host "  seeded  $wslCfg  (review it, then run: wsl --shutdown)" -ForegroundColor Green
} else {
    Write-Host "  exists  $wslCfg  (left as-is; compare against wsl\windows.wslconfig.example)" -ForegroundColor DarkYellow
}

# --- 5. seed local override + gitconfig.local ---------------------------------
$localPs = Join-Path $RepoRoot 'powershell\local.ps1'
if (-not (Test-Path $localPs)) { Copy-Item (Join-Path $RepoRoot 'powershell\local.ps1.example') $localPs }

$gcLocal = Join-Path $HOME '.gitconfig.local'
if (-not (Test-Path $gcLocal)) {
@"
[user]
    name  = YOUR NAME
    email = you@example.com
"@ | Set-Content $gcLocal -Encoding UTF8
    Write-Host "  seeded  $gcLocal  (set your git name/email)" -ForegroundColor Green
}

# --- 6. global gitignore wiring ----------------------------------------------
# Nothing to do: git\.gitconfig already sets `excludesfile = ~/.gitignore_global`,
# and that file is symlinked to ~/.gitconfig above. Running `git config --global`
# here would rewrite that line in-place with a machine-specific ABSOLUTE path,
# silently dirtying the tracked repo file (it edits the symlink target).

Write-Host ''
Write-Host 'Bootstrap complete. Open a NEW PowerShell window (pwsh) to load the profile.' -ForegroundColor Green
Write-Host 'Then: set your name/email in ~/.gitconfig.local, review ~/.wslconfig, and run `wsl --shutdown`.' -ForegroundColor Green
