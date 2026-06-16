# ============================================================================
#  install.ps1  -  bootstrap the Windows host
#
#  Usage (from the repo root):
#      .\install.ps1                 # packages + symlinks
#      .\install.ps1 -SkipPackages   # just (re)wire the symlinks
#      .\install.ps1 -DryRun         # preview every change, touch nothing
#      .\install.ps1 -NonInteractive # never prompt (CI / unattended)
#      .\install.ps1 -Help           # this banner
#
#  Symlinks require either Developer Mode (Settings > System > For developers)
#  OR an elevated shell. The script detects this and falls back to copying
#  with a warning if neither is available.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$SkipPackages,
    # Preview mode: print exactly what WOULD change (link / copy / back up / seed)
    # and mutate nothing. The safe way to inspect a bootstrap before trusting it.
    [switch]$DryRun,
    # Never prompt (overwrite confirmations, git identity). For CI / unattended
    # runs; existing real files are backed up automatically and identity is left
    # as a placeholder, exactly like the old behaviour.
    [switch]$NonInteractive,
    # Auto-confirm overwrite prompts without going fully non-interactive.
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Reuse the fleet's shared rendering helpers (Write-DotErr / Write-DotWarn /
# Get-DotGlyph / NO_COLOR-aware Write-DotHost). 05-lib is pure and side-effect-free
# on load, so the bootstrap and the daily profile share ONE error/colour layout.
$LibPath = Join-Path $RepoRoot 'powershell\core\05-lib.ps1'
if (Test-Path $LibPath) { . $LibPath }

# --- usage banner (pure: returns the lines, so -Help and the test agree) -------
function Get-InstallUsage {
    @(
        'install.ps1 - bootstrap the Windows host (packages + config symlinks)'
        ''
        'USAGE'
        '  .\install.ps1 [-SkipPackages] [-DryRun] [-NonInteractive] [-Yes] [-Help]'
        ''
        'OPTIONS'
        '  -SkipPackages    Skip scoop/winget/module install; only (re)wire links.'
        '  -DryRun          Preview every change and mutate nothing.'
        '  -NonInteractive  Never prompt (CI/unattended); back up + replace silently.'
        '  -Yes             Auto-confirm overwrite prompts.'
        '  -Help            Show this help and exit.'
        ''
        'EXAMPLES'
        '  .\install.ps1                 # full bootstrap'
        '  .\install.ps1 -DryRun         # see what it would do'
        '  .\install.ps1 -SkipPackages   # just re-link configs'
    )
}

if ($Help) { Get-InstallUsage | ForEach-Object { Write-Host $_ }; return }

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

# --- run accounting + UI --------------------------------------------------------
# A single tally Link-Item updates, summarized at the end so the run reports what
# actually changed (linked/copied/skipped/backed-up) instead of scrolling past.
$script:LinkStats = [ordered]@{ linked = 0; copied = 0; skipped = 0; backedup = 0 }

# Numbered, consistent section header (visual hierarchy + progress: [n/total]).
$script:StepTotal = 5
$script:StepNo    = 0
function Write-Step {
    param([string]$Title)
    $script:StepNo++
    Write-Host ''
    Write-Host ("[{0}/{1}] " -f $script:StepNo, $script:StepTotal) -ForegroundColor Cyan -NoNewline
    Write-Host $Title -ForegroundColor White
}

# Pure: turn the stats tally into the summary lines (unit-tested).
function Get-InstallSummaryLines {
    param([System.Collections.IDictionary]$Stats)
    @(
        "linked   : $($Stats.linked)"
        "copied   : $($Stats.copied)"
        "skipped  : $($Stats.skipped)  (already correct)"
        "backed up: $($Stats.backedup)"
    )
}

# --- overwrite confirmation ----------------------------------------------------
# A REAL (non-symlink) file at $Link is the user's own config; backing it up and
# replacing it without asking is the one genuinely destructive thing the bootstrap
# does. Prompt before doing it, unless told otherwise. A wrong/stale symlink (one
# of ours) is rewired silently — there's nothing to lose.
function Confirm-Overwrite {
    param([string]$Link)
    if ($Yes -or $NonInteractive) { return $true }
    $item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'SymbolicLink') { return $true }
    try { $ans = Read-Host "  '$Link' exists. Back up and replace? [Y/n]" }
    catch { return $true }   # no interactive host: fall back to the old auto-backup
    return ($ans -eq '' -or $ans -match '^(y|yes)$')
}

# --- link helper --------------------------------------------------------------
function Link-Item {
    param([string]$Target, [string]$Link)

    $verb = if ($CanSymlink) { 'link' } else { 'copy' }

    # Idempotent: a link already pointing where we want needs no work — skip it so
    # repeated runs don't pile up `.bak` files. Only real files, or wrong/stale
    # links, get backed up and replaced.
    if ($CanSymlink -and (Test-SymlinkCurrent -Link $Link -Target $Target)) {
        Write-Host "  ok      $Link (already linked)" -ForegroundColor DarkGray
        $script:LinkStats.skipped++
        return
    }

    # Dry-run: report the action and mutate nothing (no mkdir, no backup, no link).
    if ($script:DryRun) {
        if (Test-Path $Link) { Write-DotHost "  would back up + $verb  $Link" -Color DarkYellow }
        else                 { Write-DotHost "  would $verb  $Link" -Color Cyan }
        return
    }

    $parent = Split-Path -Parent $Link
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    if (Test-Path $Link) {
        if (-not (Confirm-Overwrite $Link)) {
            Write-Host "  skip    $Link (kept existing, by request)" -ForegroundColor DarkGray
            $script:LinkStats.skipped++
            return
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Move-Item $Link "$Link.$stamp.bak" -Force
        Write-DotHost "  backed up existing -> $Link.$stamp.bak" -Color DarkYellow
        $script:LinkStats.backedup++
    }
    if ($CanSymlink) {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force | Out-Null
        Write-DotHost "  linked  $Link" -Color Green
        $script:LinkStats.linked++
    } else {
        # -Recurse so directory targets (nvim\, psmux\scripts) copy in full — a
        # plain Copy-Item only takes the top-level entry and leaves them empty.
        $recurse = (Test-Path $Target -PathType Container)
        Copy-Item $Target $Link -Force -Recurse:$recurse
        Write-DotHost "  copied  $Link" -Color Green
        $script:LinkStats.copied++
    }
}

# Library-only hook: dot-sourcing with DOTFILES_INSTALL_LIBONLY=1 exposes the
# functions above (for the test suite) without running the bootstrap below.
if ($env:DOTFILES_INSTALL_LIBONLY -eq '1') { return }

# Promote -DryRun to script scope so Link-Item (defined above) sees it.
$script:DryRun = [bool]$DryRun

if ($script:DryRun) {
    Write-Host ''
    Write-DotHost ' DRY RUN ' -Color Cyan
    Write-DotHost ' nothing will be installed, linked, copied, or written.' -Color DarkGray
}

# --- transcript log (B11) -----------------------------------------------------
# Capture the whole run to a timestamped log so a "it broke on machine X" report
# has something concrete to attach. Best-effort: skipped in dry-run and on hosts
# that don't support transcription.
$script:Transcribing = $false
if (-not $script:DryRun -and $env:LOCALAPPDATA) {
    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'dotfiles\logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $logFile = Join-Path $logDir ("install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Start-Transcript -Path $logFile -Force | Out-Null
        $script:Transcribing = $true
    } catch { }
}

# Wrap the bootstrap so a Ctrl-C (or a thrown error) still prints where it stopped
# and closes the transcript, instead of dumping the user at a bare prompt with a
# half-wired host and no acknowledgement (U2: graceful interrupts).
$script:Completed = $false
try {

# --- preflight: shell version, Mark-of-the-Web, execution policy --------------
# Warn (do not block) if running under Windows PowerShell 5.1. Bootstrapping
# from 5.1 is fine - this run installs pwsh 7 - but the profile is wired for
# pwsh, so daily work should happen there afterward.
if ($PSVersionTable.PSEdition -ne 'Core') {
    Write-DotWarn 'Running under Windows PowerShell 5.1.' 'Do daily work in PowerShell 7 (pwsh) afterward — the profile targets the pwsh path.'
}

# Strip the "downloaded from the internet" flag off the repo so RemoteSigned
# policy will not block our own scripts. A `git clone` avoids this entirely;
# this matters when the repo arrived as a downloaded archive. Skip the .git tree:
# its thousands of objects never get loaded/executed and only slow the scan.
if ($script:DryRun) {
    Write-DotHost '  would unblock repo files + ensure RemoteSigned execution policy' -Color Cyan
} else {
    Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\.git\*' } |
        Unblock-File -ErrorAction SilentlyContinue

    # Ensure scripts can run for this user. RemoteSigned is the minimum the profile
    # needs to load each session. Leave it alone if Group Policy already pins one.
    try {
        $cur = Get-ExecutionPolicy -Scope CurrentUser
        if ($cur -notin 'RemoteSigned','Unrestricted','Bypass') {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Host 'Set CurrentUser execution policy to RemoteSigned.' -ForegroundColor DarkGray
        }
    } catch {
        Write-DotWarn "Could not set execution policy (Group Policy may control it): $_"
    }
}

$CanSymlink = Test-CanSymlink
if (-not $CanSymlink) {
    Write-DotWarn 'Neither Developer Mode nor admin detected — falling back to COPY (changes will not auto-track the repo).' 'For true symlinks: enable Developer Mode, or re-run from an elevated PowerShell.'
}

# Wire the repo-local pre-commit gate when this is a git clone (so contributors
# get the dependency-free validator on every commit). Harmless for users.
if (Test-Path (Join-Path $RepoRoot '.git')) {
    if ($script:DryRun) {
        Write-DotHost '  would set git core.hooksPath = .githooks' -Color Cyan
    } else {
        git -C $RepoRoot config core.hooksPath .githooks 2>$null
        Write-Host '  git hooks: core.hooksPath = .githooks (pre-commit validation)' -ForegroundColor DarkGray
    }
}

# --- 1. persistent env var ----------------------------------------------------
Write-Step 'Setting DOTFILES_WIN'
if ($script:DryRun) {
    Write-DotHost "  would set DOTFILES_WIN = $RepoRoot (User)" -Color Cyan
} else {
    [Environment]::SetEnvironmentVariable('DOTFILES_WIN', $RepoRoot, 'User')
    $env:DOTFILES_WIN = $RepoRoot
    Write-Host "  DOTFILES_WIN = $RepoRoot" -ForegroundColor DarkGray
}

# --- 2. packages --------------------------------------------------------------
Write-Step $(if ($SkipPackages) { 'Installing packages (skipped: -SkipPackages)' } else { 'Installing packages' })
if (-not $SkipPackages) {
    if ($script:DryRun) {
        Write-DotHost '  would install scoop + winget + PowerShell-module packages' -Color Cyan
    } else {
        & (Join-Path $RepoRoot 'packages\Install-Packages.ps1')
    }
}

# --- 3. wire symlinks ---------------------------------------------------------
Write-Step 'Wiring configs'

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
    if ($script:DryRun) {
        Write-DotHost "  would clone psmux-plugins and install ppm -> $ppmDir" -Color Cyan
    } else {
        $tmp = Join-Path $env:TEMP ('psmux-plugins-' + [guid]::NewGuid().ToString('N'))
        try {
            git clone --depth 1 https://github.com/psmux/psmux-plugins.git $tmp
            if ($LASTEXITCODE -eq 0) {
                New-Item -ItemType Directory -Force -Path (Split-Path $ppmDir) | Out-Null
                Copy-Item (Join-Path $tmp 'ppm') $ppmDir -Recurse -Force
                Write-DotHost "  installed ppm -> $ppmDir" -Color Green
            } else {
                Write-DotWarn 'ppm clone failed.' 'Clone psmux-plugins by hand, copy ppm\ to ~\.psmux\plugins\ppm'
            }
        } finally {
            if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

# Windows Terminal settings (Store install path)
$wtDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
if (Test-Path $wtDir) {
    Link-Item -Target (Join-Path $RepoRoot 'windows-terminal\settings.json') -Link (Join-Path $wtDir 'settings.json')
} else {
    Write-DotWarn 'Windows Terminal LocalState not found.' 'If you installed WT via scoop, link settings.json manually.'
}

# --- 4. .wslconfig (COPY, don't symlink - it's host-global, edit per machine) -
Write-Step 'Seeding host-global .wslconfig'
$wslCfg = Join-Path $HOME '.wslconfig'
if (Test-Path $wslCfg) {
    Write-DotHost "  exists  $wslCfg  (left as-is; compare against wsl\windows.wslconfig.example)" -Color DarkYellow
} elseif ($script:DryRun) {
    Write-DotHost "  would seed $wslCfg from wsl\windows.wslconfig.example" -Color Cyan
} else {
    Copy-Item (Join-Path $RepoRoot 'wsl\windows.wslconfig.example') $wslCfg
    Write-DotHost "  seeded  $wslCfg  (review it, then run: wsl --shutdown)" -Color Green
}

# --- 5. seed local override + gitconfig.local ---------------------------------
Write-Step 'Seeding local overrides'
$localPs = Join-Path $RepoRoot 'powershell\local.ps1'
if (-not (Test-Path $localPs)) {
    if ($script:DryRun) { Write-DotHost "  would seed $localPs from local.ps1.example" -Color Cyan }
    else { Copy-Item (Join-Path $RepoRoot 'powershell\local.ps1.example') $localPs }
}

# Zero-config onboarding (U9): instead of seeding a placeholder the user must
# remember to hand-edit, ask for the git identity up front. Falls back to the
# placeholder when non-interactive, in dry-run, or when input is left blank
# (dotfiles-doctor still flags a placeholder, so nothing is silently wrong).
$gcLocal = Join-Path $HOME '.gitconfig.local'
if (-not (Test-Path $gcLocal)) {
    $gitName = 'YOUR NAME'; $gitEmail = 'you@example.com'
    if (-not $NonInteractive -and -not $script:DryRun) {
        try {
            $n = Read-Host '  git author name  (blank to fill in later)'
            $e = Read-Host '  git author email (blank to fill in later)'
            if ($n.Trim()) { $gitName  = $n.Trim() }
            if ($e.Trim()) { $gitEmail = $e.Trim() }
        } catch { }   # no interactive host: keep the placeholders
    }
    if ($script:DryRun) {
        Write-DotHost "  would seed $gcLocal (git identity)" -Color Cyan
    } else {
@"
[user]
    name  = $gitName
    email = $gitEmail
"@ | Set-Content $gcLocal -Encoding UTF8
        $note = if ($gitName -eq 'YOUR NAME') { '  (set your git name/email)' } else { "  ($gitName <$gitEmail>)" }
        Write-DotHost "  seeded  $gcLocal$note" -Color Green
    }
}

# --- 6. global gitignore wiring ----------------------------------------------
# Nothing to do: git\.gitconfig already sets `excludesfile = ~/.gitignore_global`,
# and that file is symlinked to ~/.gitconfig above. Running `git config --global`
# here would rewrite that line in-place with a machine-specific ABSOLUTE path,
# silently dirtying the tracked repo file (it edits the symlink target).

$rule = if (Test-DotUnicode) { '─' * 56 } else { '-' * 56 }
Write-Host ''
Write-DotHost "-- Summary $rule" -Color Cyan
Get-InstallSummaryLines -Stats $script:LinkStats | ForEach-Object { Write-DotHost "  $_" -Color Gray }
if (-not $CanSymlink) {
    Write-DotHost '  mode    : COPY (no Dev Mode / not elevated — links would not track the repo)' -Color DarkYellow
}

Write-Host ''
if ($script:DryRun) {
    Write-DotHost 'Dry run complete — re-run without -DryRun to apply.' -Color Cyan
} else {
    Write-DotHost 'Bootstrap complete.' -Color Green
    Write-Host 'Next steps:' -ForegroundColor White
    Write-Host '  1. Open a NEW PowerShell window (pwsh) to load the profile.' -ForegroundColor Gray
    Write-Host '  2. Set your name/email in ~/.gitconfig.local.' -ForegroundColor Gray
    Write-Host '  3. Review ~/.wslconfig, then run: wsl --shutdown' -ForegroundColor Gray
    Write-Host '  4. Run `dotfiles-doctor` to verify everything is wired correctly.' -ForegroundColor Gray
}

$script:Completed = $true

} finally {
    # Runs on normal completion, on a thrown error, AND on Ctrl-C — so an
    # interrupted bootstrap acknowledges itself and leaves a readable log.
    if (-not $script:Completed) {
        Write-Host ''
        Write-DotWarn 'Bootstrap did not finish (interrupted or errored).' 'Re-run .\install.ps1 — it is idempotent and resumes cleanly.'
        if ($script:LinkStats) {
            Get-InstallSummaryLines -Stats $script:LinkStats | ForEach-Object { Write-DotHost "  $_" -Color Gray }
        }
    }
    if ($script:Transcribing) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-DotHost "  log: $logFile" -Color DarkGray
    }
}
