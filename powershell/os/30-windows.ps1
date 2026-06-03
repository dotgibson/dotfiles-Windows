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
function update-host {
    Write-Host '== scoop ==' -ForegroundColor Cyan
    if (Test-Cmd scoop)  { scoop update *; scoop cleanup * }
    Write-Host '== winget ==' -ForegroundColor Cyan
    if (Test-Cmd winget) { winget upgrade --all --include-unknown }
    Write-Host 'done.' -ForegroundColor Green
}

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
        Start-Process pwsh -Verb RunAs -ArgumentList ('-NoExit','-Command',($args -join ' '))
    } else {
        Start-Process pwsh -Verb RunAs
    }
}

# --- env var helpers ----------------------------------------------------------
function setenv  { param($Name,$Value) [Environment]::SetEnvironmentVariable($Name,$Value,'User'); Set-Item "env:$Name" $Value }
function getenv  { param($Name) [Environment]::GetEnvironmentVariable($Name,'User') }

# --- Start PSmux Session ------------------------------------------------------
# Prevent psmux from launching if it is already running in the current session
if (-not $env:TMUX) {
    # Optional: Automatically attach to an existing session, or create a new one
    psmux attach -t main 2>$null || psmux new-session -s main
  }
