# ============================================================================
#  os/33-psmux-pill.ps1  -  the psmux operator/VPN status pill (no elevation)
#
#  The status bar must never spawn pwsh on its render path — psmux expands
#  status-right SYNCHRONOUSLY while building each client's state push, so a cold
#  pwsh `#()` stalls the first paint (that was the "blank screen, blinking cursor"
#  bug). So the operator/VPN pill is file-backed: something writes the styled pill
#  to a cache file out of band, and the bar just reads that file with a cheap
#  `type` (~10ms cmd builtin, no pwsh).
#
#  The "something" is an IN-SESSION TIMER, not a Scheduled Task. A System.Timers
#  .Timer registered in the pane's own pwsh refreshes the file every 60s. Why not
#  a Scheduled Task? Registering one needs rights many machines withhold from a
#  non-elevated shell ("Access is denied"). The timer needs no elevation, runs only
#  while a psmux pane is open (exactly when the bar is visible), writes on a
#  background thread (never blocks your prompt), and dies with the shell — no
#  orphaned daemons. Multiple panes cooperate via the cache file's mtime so they
#  don't all do the work.
#
#    psmux-pill-enable [-AllNetworks]   turn it on (persists; new panes auto-start)
#    psmux-pill-disable                 turn it off and blank the segment
#    psmux-pill-now [-AllNetworks]      refresh the cache file once, now
#    psmux-pill-status                  refresher state + current cached pill
#
#  -AllNetworks also shows the plain-LAN IP (green) when no tunnel is up. Default
#  is tunnel-only: the pill is invisible unless you're on a VPN, keeping the bar
#  quiet. The status-right segment in psmux.conf reads %LOCALAPPDATA%\dotfiles\
#  psmux-netinfo.pill — until you enable the pill that file never exists and the
#  segment renders nothing (the bar stays clock + cwd only).
#
#  Loads automatically (profile.ps1 globs os/ in name order, after 32-psmux).
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: psmux-pill-now, psmux-pill-enable, psmux-pill-disable, psmux-pill-status
# requires: Test-Cmd, Test-InMux, Write-DotErr, Write-DotHost, Write-DotOk

if (-not (Test-Cmd psmux)) { return }

$script:PillCache  = Join-Path $env:LOCALAPPDATA 'dotfiles\psmux-netinfo.pill'
$script:PillSource = 'PsmuxPillRefresh'   # Register-ObjectEvent SourceIdentifier

# Pane detection (Test-InMux — "is the bar showing?") is shared from
# core/05-lib.ps1 now, so it can't drift from the psmux auto-attach guard's copy.

function script:Get-PillScript {
    $p = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'psmux\scripts\psmux-netinfo.ps1' } else { $null }
    if (-not $p -or -not (Test-Path $p)) {
        Write-DotErr "psmux-pill: netinfo script not found at $p" 're-run install.ps1 -SkipPackages to relink the psmux scripts'
        return $null
    }
    return $p
}

# psmux-pill-now — write the cache file once, synchronously, in the foreground.
function psmux-pill-now {
    [CmdletBinding()] param([switch]$AllNetworks)
    $netScript = Get-PillScript
    if (-not $netScript) { return }
    if ($AllNetworks) { & $netScript -AllNetworks | Out-Null } else { & $netScript | Out-Null }
    Write-DotHost "refreshed -> $script:PillCache" -Color DarkGray
}

# Start-PillRefresher — arm the per-session timer (idempotent within a session).
function script:Start-PillRefresher {
    param([int]$IntervalSeconds = 60, [switch]$AllNetworks)
    if ($global:PsmuxPillTimer) { return }           # already armed in this pwsh
    $netScript = Get-PillScript
    if (-not $netScript) { return }

    $steadyMs = [math]::Max(5, $IntervalSeconds) * 1000

    $timer = New-Object System.Timers.Timer
    # CRITICAL: do NOT prime synchronously here — psmux-netinfo.ps1's Get-Net*/WMI
    # calls take SECONDS, and running them at profile-load time blocked every new
    # shell/pane by that much (this fragment was ~10s of startup). Instead the
    # FIRST refresh is just an early timer tick (~2.5s) that runs on the timer's
    # background thread; the handler then settles the cadence to the steady value.
    # Net effect: arming the pill costs ~milliseconds at load; the WMI work happens
    # off the startup path.
    $timer.Interval  = 2500
    $timer.AutoReset = $true

    # The Elapsed action runs in its own runspace and only sees $Event — pass
    # everything it needs via -MessageData (no closure over this scope).
    $data = @{
        Script   = $netScript
        All      = [bool]$AllNetworks
        OutFile  = $script:PillCache
        MinAge   = [math]::Max(2, [int]($IntervalSeconds / 2))   # cross-pane dedup window
        SteadyMs = $steadyMs
    }
    $null = Register-ObjectEvent -InputObject $timer -EventName Elapsed `
        -SourceIdentifier $script:PillSource -MessageData $data -Action {
            $d = $Event.MessageData
            $Sender.Interval = $d.SteadyMs    # after the quick first tick, settle to the steady cadence
            try {
                # If another pane refreshed the file very recently, skip the work.
                if ((Test-Path $d.OutFile) -and
                    (([DateTime]::UtcNow - (Get-Item $d.OutFile).LastWriteTimeUtc).TotalSeconds -lt $d.MinAge)) { return }
                if ($d.All) { & $d.Script -AllNetworks | Out-Null } else { & $d.Script | Out-Null }
            } catch { }
        }
    $timer.Start()
    $global:PsmuxPillTimer = $timer
}

function script:Stop-PillRefresher {
    if ($global:PsmuxPillTimer) {
        try { $global:PsmuxPillTimer.Stop(); $global:PsmuxPillTimer.Dispose() } catch { }
        $global:PsmuxPillTimer = $null
    }
    Unregister-Event -SourceIdentifier $script:PillSource -ErrorAction SilentlyContinue
}

# psmux-pill-enable — persist the opt-in (User env var, so new panes auto-start
# it at shell load) and arm it in the current session right now. No elevation.
function psmux-pill-enable {
    [CmdletBinding()] param([switch]$AllNetworks)
    [Environment]::SetEnvironmentVariable('DOTFILES_PSMUX_PILL', '1', 'User')
    $env:DOTFILES_PSMUX_PILL = '1'
    if ($AllNetworks) {
        [Environment]::SetEnvironmentVariable('DOTFILES_PSMUX_PILL_ALL', '1', 'User')
        $env:DOTFILES_PSMUX_PILL_ALL = '1'
    }
    Start-PillRefresher -AllNetworks:$AllNetworks
    Write-DotOk 'psmux pill enabled — in-session refresher (no scheduled task, no elevation)'
    Write-DotHost '  refreshes every 60s while a psmux pane is open; new panes auto-arm it.' -Color DarkGray
    if (-not (Test-InMux)) {
        Write-DotHost '  (not inside psmux now — it kicks in when you `mux`.)' -Color DarkGray
    } else {
        Write-DotHost '  the bar picks it up within one status-interval; force a repaint with prefix + r.' -Color DarkGray
    }
}

# psmux-pill-disable — stop the refresher, drop the opt-in, blank the segment.
function psmux-pill-disable {
    [Environment]::SetEnvironmentVariable('DOTFILES_PSMUX_PILL', $null, 'User')
    [Environment]::SetEnvironmentVariable('DOTFILES_PSMUX_PILL_ALL', $null, 'User')
    Remove-Item Env:DOTFILES_PSMUX_PILL, Env:DOTFILES_PSMUX_PILL_ALL -ErrorAction SilentlyContinue
    Stop-PillRefresher
    Remove-Item $script:PillCache -Force -ErrorAction SilentlyContinue
    Write-DotOk 'psmux pill disabled (refresher stopped in this session; cache cleared)'
    Write-DotHost '  other open panes keep their timer until they close — or run this in each.' -Color DarkGray
}

function psmux-pill-status {
    $armed   = [bool]$global:PsmuxPillTimer
    $enabled = ($env:DOTFILES_PSMUX_PILL -eq '1')
    [pscustomobject]@{
        Enabled          = $enabled
        ArmedThisSession = $armed
        InsideMux        = (Test-InMux)
        AllNetworks      = ($env:DOTFILES_PSMUX_PILL_ALL -eq '1')
        Cache            = $script:PillCache
    } | Format-List
    if (Test-Path $script:PillCache) {
        $raw = [System.IO.File]::ReadAllText($script:PillCache)
        if ([string]::IsNullOrEmpty($raw)) {
            Write-DotHost 'pill cache is empty (no tunnel up; pass -AllNetworks to show LAN too)' -Color DarkGray
        } else {
            Write-DotHost "pill cache: $raw" -Color DarkGray
        }
    } else {
        Write-DotHost "no pill cache yet at $script:PillCache (run psmux-pill-enable)" -Color DarkGray
    }
}

# --- auto-arm in opted-in psmux panes -----------------------------------------
# Only inside a psmux pane (where the bar shows) and only if you've opted in.
# Env var is read at shell start, so a freshly-opened pane arms itself.
if ($env:DOTFILES_PSMUX_PILL -eq '1' -and (Test-InMux)) {
    Start-PillRefresher -AllNetworks:($env:DOTFILES_PSMUX_PILL_ALL -eq '1')
}
