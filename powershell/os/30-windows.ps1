# ============================================================================
#  os/30-windows.ps1  -  native Windows host helpers (scoop / winget / paths)
# ============================================================================

# --- scoop (your primary CLI package manager on the host) ---------------------
if (Test-Cmd scoop) {
    function scu  { scoop update * @args }            # update all apps
    function scs  { scoop search @args }
    function sci  { scoop install @args }
    function scl  { scoop list @args }
    function sccl { scoop cleanup * ; scoop cache rm * }
}

# --- winget (GUI apps + things not in scoop) ----------------------------------
if (Test-Cmd winget) {
    function wgu { winget upgrade --all --include-unknown }
    function wgs { param($q) winget search $q }
    function wgi { param($id) winget install --id $id -e }
}

# --- full host update in one shot ---------------------------------------------
# Delegates to `up` (core/15-update.ps1) which also clears the nudge cache.
# Kept as a muscle-memory alias; `up` is the canonical implementation.
function update-host { up @args }

# --- PATH inspection ----------------------------------------------------------
function path { $env:PATH -split ';' | Where-Object { $_ } }

# --- reveal in Explorer / open ------------------------------------------------
function open { param($Target = '.') Invoke-Item $Target }
Set-Alias explorer-here open

# --- elevate the current shell (sudo-ish) -------------------------------------
# Windows 11 has a native `sudo`; fall back to a Start-Process relaunch.
function admin {
    if (Test-Cmd sudo) { sudo @args; return }
    if ($args.Count -gt 0) {
        # Re-quote any argument that contains whitespace so a relaunched command
        # like `admin code "C:\Program Files\x"` survives the join into -Command
        # instead of being split into separate tokens.
        $cmd = ($args | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '`"') + '"' } else { "$_" }
        }) -join ' '
        Start-Process pwsh -Verb RunAs -ArgumentList @('-NoExit', '-Command', $cmd)
    } else {
        Start-Process pwsh -Verb RunAs
    }
}

# --- env var helpers ----------------------------------------------------------
function setenv  { param($Name,$Value) [Environment]::SetEnvironmentVariable($Name,$Value,'User'); Set-Item "env:$Name" $Value }
function getenv  { param($Name) [Environment]::GetEnvironmentVariable($Name,'User') }

# --- modules-localize: move PowerShell modules OFF OneDrive (one-time) ---------
# Importing modules from a OneDrive-synced Documents\PowerShell\Modules folder
# adds seconds to every shell start. profile.ps1 already prepends a local modules
# dir to $env:PSModulePath; this copies your existing CurrentUser modules there so
# imports resolve from local disk. Run it ONCE, ideally from `pwsh -NoProfile` so
# no module DLLs are locked. Idempotent — safe to re-run.
function modules-localize {
    $src = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
    $dst = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
    if (-not (Test-Path $src)) { Write-Host "no user modules at $src (nothing to move)"; return }
    if ($src -notlike '*OneDrive*') {
        Write-Host "your modules path isn't under OneDrive ($src) — no move needed." -ForegroundColor DarkYellow
    }
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Write-Host "copying modules to local disk" -ForegroundColor Cyan
    Write-Host "  from $src" -ForegroundColor DarkGray
    Write-Host "  to   $dst" -ForegroundColor DarkGray
    # /E copy (not /MOVE): leaves the OneDrive copies in place so a module loaded
    # in THIS session can't block the operation. The prepend makes the local copy
    # win regardless; delete the OneDrive Modules folder by hand later if you like.
    robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-DotErr "robocopy failed (exit $LASTEXITCODE)" 'check that the source/destination paths are writable, then retry'; return }
    Write-Host "done — open a NEW shell. Modules now load from $dst (off OneDrive)." -ForegroundColor Green
    Write-Host "verify with: (Get-Module -ListAvailable PSReadLine).Path" -ForegroundColor DarkGray
}

# --- Start psmux session (top-level interactive shell only) -------------------
# $inMux must list every marker psmux sets inside a pane. Confirm with:
#   Get-ChildItem env: | Where-Object Name -match 'mux'
# and add whatever you find. The sentinel is a fallback in case psmux
# doesn't export a marker into pane shells.
$InMux = $env:TMUX -or $env:TMUX_PANE -or $env:PSMUX -or $env:PSMUX_PANE

# Only auto-launch for a *top-level interactive* shell. The profile is ALSO
# loaded for `pwsh -Command ...` / `pwsh -File ...` (VS Code tasks, git hooks,
# scheduled scripts, other tooling) unless they pass -NoProfile — and attaching
# a multiplexer there would hang or hijack the scripted call. Inspect the actual
# process command line: anything that ran a command/file/encoded-block, or asked
# for a non-interactive host, is NOT a shell we should drop into psmux for.
function script:Test-InteractiveShell {
    if ($Host.Name -ne 'ConsoleHost') { return $false }      # ISE/VSCode-host/remoting
    # PowerShell accepts any unambiguous prefix of a parameter name, so match by
    # prefix rather than exact spelling. We must NOT match -NoExit/-NoLogo/
    # -NoProfile (all begin 'no' and DO appear on interactive launches, e.g. the
    # Windows Terminal profile's `pwsh.exe -NoLogo`), so -NonInteractive only
    # counts once the token is long enough to be unambiguous ('noni'+).
    $nonInteractive = @('command', 'file', 'encodedcommand', 'noninteractive')
    foreach ($a in [Environment]::GetCommandLineArgs()) {
        if ($a -notmatch '^-') { continue }
        $name = $a.TrimStart('-').ToLowerInvariant()
        if (-not $name) { continue }
        foreach ($flag in $nonInteractive) {
            if ($flag.StartsWith($name)) {
                if ($flag -eq 'noninteractive' -and $name.Length -lt 4) { continue }
                return $false
            }
        }
    }
    return $true
}

# Escape hatch: set PSMUX_NO_AUTOLAUNCH=1 to suppress the auto-attach and stay in
# a bare pwsh shell (parity with FAST_START / DOTFILES_UPDATE_CHECK). Read from the
# ENVIRONMENT, so it must be set before pwsh starts — for a one-off lean shell:
#   $env:PSMUX_NO_AUTOLAUNCH='1'; pwsh        # child inherits it
# or permanently on this box:
#   [Environment]::SetEnvironmentVariable('PSMUX_NO_AUTOLAUNCH','1','User')
# This is the off-switch to reach for if psmux ever misbehaves on launch and you
# need a prompt without it (you can still run `mux` by hand afterward).
if ((Test-Cmd psmux) -and -not $InMux -and -not $env:PSMUX_AUTOLAUNCHED -and
    $env:PSMUX_NO_AUTOLAUNCH -ne '1' -and
    (Test-InteractiveShell)) {
    $env:PSMUX_AUTOLAUNCHED = '1'
    psmux new-session -A -s main
}
