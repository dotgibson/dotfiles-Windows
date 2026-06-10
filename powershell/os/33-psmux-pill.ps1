# ============================================================================
#  os/33-psmux-pill.ps1  -  control surface for the psmux operator/VPN status pill
#
#  The status bar must never spawn pwsh on its render path — psmux expands
#  status-right SYNCHRONOUSLY while building each client's state push, so a cold
#  pwsh `#()` stalls the first paint (that was the "blank screen, blinking cursor"
#  bug). So the operator/VPN pill is file-backed instead: a tiny Scheduled Task
#  runs psmux/scripts/psmux-netinfo.ps1 out of band, which writes the styled pill
#  to a cache file; the bar reads that file with a cheap `type` (~10ms cmd builtin,
#  no pwsh). Tunnel state changes rarely, so a 1-minute cadence is plenty.
#
#    psmux-pill-install [-IntervalMinutes N] [-AllNetworks]
#                              register + enable the refresh task (default 1 min)
#    psmux-pill-now [-AllNetworks]   refresh the cache file once, now
#    psmux-pill-status               task state + current cached pill
#    psmux-pill-uninstall            remove the task and clear the cache
#
#  -AllNetworks also shows the plain-LAN IP (green) when no tunnel is up. Default
#  is tunnel-only: the pill is invisible unless you're on a VPN, keeping the bar
#  quiet. The status-right segment in psmux.conf reads %LOCALAPPDATA%\dotfiles\
#  psmux-netinfo.pill — if you never install the task, that file never exists and
#  the segment simply renders nothing (the bar stays clock+cwd only).
#
#  Loads automatically (profile.ps1 globs os/ in name order, after 32-psmux).
# ============================================================================

if (-not (Test-Cmd psmux)) { return }

$script:PillTaskName = 'dotfiles-psmux-pill'
$script:PillCache    = Join-Path $env:LOCALAPPDATA 'dotfiles\psmux-netinfo.pill'

function script:Get-PillScript {
    $p = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'psmux\scripts\psmux-netinfo.ps1' } else { $null }
    if (-not $p -or -not (Test-Path $p)) {
        Write-Error "psmux-pill: netinfo script not found at $p"
        return $null
    }
    return $p
}

# psmux-pill-now — write the cache file once, synchronously, in the foreground.
# Handy to populate it immediately (install calls it) or to test the detection.
function psmux-pill-now {
    [CmdletBinding()] param([switch]$AllNetworks)
    $netScript = Get-PillScript
    if (-not $netScript) { return }
    if ($AllNetworks) { & $netScript -AllNetworks | Out-Null } else { & $netScript | Out-Null }
    Write-Host "refreshed -> $script:PillCache" -ForegroundColor DarkGray
}

# psmux-pill-install — register the Scheduled Task that keeps the cache fresh.
# Runs as the current user (so $env:LOCALAPPDATA matches what the bar's `type`
# reads) and needs no elevation, same as maint-install.
function psmux-pill-install {
    [CmdletBinding()]
    param(
        [int]$IntervalMinutes = 1,   # Task Scheduler's practical floor is 1 minute
        [switch]$AllNetworks
    )
    $netScript = Get-PillScript
    if (-not $netScript) { return }
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-Error 'psmux-pill: pwsh (PowerShell 7) not found on PATH'; return }
    if ($IntervalMinutes -lt 1) { $IntervalMinutes = 1 }

    $netFlag = if ($AllNetworks) { ' -AllNetworks' } else { '' }
    $action  = New-ScheduledTaskAction -Execute $pwshPath `
        -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"{1}' -f $netScript, $netFlag)

    # Run every N minutes, indefinitely. New-ScheduledTaskTrigger can't express an
    # endless repetition on its own, so build a one-shot trigger and graft a
    # repetition spec onto it (the well-known way to dodge the MaxValue-duration
    # bug). Plus an AtLogOn trigger so the pill is fresh the moment you sign in.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration  (New-TimeSpan -Days 3650)).Repetition
    $triggerLogon = New-ScheduledTaskTrigger -AtLogOn

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1)

    try {
        Register-ScheduledTask -TaskName $script:PillTaskName `
            -Action $action -Trigger @($trigger, $triggerLogon) -Settings $settings `
            -Description 'dotfiles: refresh psmux operator/VPN status pill (file-backed, off the render path)' `
            -Force -ErrorAction Stop | Out-Null
        Write-Host "✓ scheduled task '$script:PillTaskName' installed (every $IntervalMinutes min)" -ForegroundColor Green
        psmux-pill-now -AllNetworks:$AllNetworks      # populate the cache right now
        Write-Host "  the bar reads it via  #(type %LOCALAPPDATA%\dotfiles\psmux-netinfo.pill)" -ForegroundColor DarkGray
        Write-Host "  reload psmux to pick up the segment: prefix + r" -ForegroundColor DarkGray
    } catch {
        Write-Error "psmux-pill-install failed: $_"
    }
}

function psmux-pill-status {
    $task = Get-ScheduledTask -TaskName $script:PillTaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "task not installed (run psmux-pill-install)" -ForegroundColor DarkYellow
    } else {
        $info = Get-ScheduledTaskInfo -TaskName $script:PillTaskName
        [pscustomobject]@{
            Task        = $task.TaskName
            State       = $task.State
            NextRunTime = $info.NextRunTime
            LastRunTime = $info.LastRunTime
            LastResult  = ('0x{0:X}' -f $info.LastTaskResult)
        } | Format-List
    }
    if (Test-Path $script:PillCache) {
        $raw = [System.IO.File]::ReadAllText($script:PillCache)
        if ([string]::IsNullOrEmpty($raw)) {
            Write-Host "pill cache is empty (no tunnel up; pass -AllNetworks to show LAN too)" -ForegroundColor DarkGray
        } else {
            Write-Host "pill cache: $raw" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "no pill cache yet at $script:PillCache" -ForegroundColor DarkGray
    }
}

function psmux-pill-uninstall {
    if (Get-ScheduledTask -TaskName $script:PillTaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $script:PillTaskName -Confirm:$false
        Write-Host "✓ removed scheduled task '$script:PillTaskName'" -ForegroundColor Green
    } else {
        Write-Host "nothing to remove (task '$script:PillTaskName' not found)" -ForegroundColor DarkYellow
    }
    # Clear the cache so the bar's status-right segment goes blank again.
    Remove-Item $script:PillCache -Force -ErrorAction SilentlyContinue
    Write-Host "  cleared $script:PillCache" -ForegroundColor DarkGray
}
