# ============================================================================
#  os/40-maint.ps1  -  control surface for the daily maintenance job.
#
#  Windows analog of Core's zsh/maint.zsh. Where the Linux/Mac fleet wires the
#  runner to systemd / launchd / cron, the Windows host uses Task Scheduler.
#  The runner itself is maint/Maintenance.ps1 (port of dotfiles-maint.sh).
#
#    maint-install [HH:MM]   register + enable the daily task (default 13:00)
#    maint-run               run it now, in the foreground
#    maint-log [N|-f]        show last N log lines (default 50), or follow (-f)
#    maint-status            when it next runs / last result
#    maint-uninstall         remove the scheduled task
#
#  `StartWhenAvailable` on the task is the Windows equivalent of systemd's
#  Persistent=true / launchd's catch-up: if the machine was off at the scheduled
#  time, the task runs at the next opportunity.
# ============================================================================

$script:MaintTaskName = 'dotfiles-maint'
$script:MaintScript   = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'maint\Maintenance.ps1' } else { $null }
$script:MaintLog      = Join-Path $env:LOCALAPPDATA 'dotfiles\maint\maint.log'
$script:FollowArgs    = @('-f', '--follow')

function Get-MaintRunnerPath {
    if (-not $script:MaintScript -or -not (Test-Path $script:MaintScript)) {
        Write-Error "maint: runner not found at $script:MaintScript"
        return $null
    }
    return $script:MaintScript
}

function Get-PwshPath {
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) {
        Write-Error 'maint: pwsh (PowerShell 7) not found on PATH'
        return $null
    }
    return $pwshPath
}

function maint-install {
    param([string]$When = '13:00')

    if ($When -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') {
        Write-Error 'usage: maint-install [HH:MM]   (24h, e.g. 13:00)'; return
    }
    $maintScript = Get-MaintRunnerPath
    if (-not $maintScript) { return }
    $pwshPath = Get-PwshPath
    if (-not $pwshPath) { return }


    $action  = New-ScheduledTaskAction -Execute $pwshPath `
                 -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $maintScript)
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]$When)
    $settings = New-ScheduledTaskSettingsSet `
                 -StartWhenAvailable `
                 -AllowStartIfOnBatteries `
                 -DontStopIfGoingOnBatteries `
                 -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    try {
        Register-ScheduledTask -TaskName $script:MaintTaskName `
            -Action $action -Trigger $trigger -Settings $settings `
            -Description 'dotfiles daily maintenance (scoop, mise, nvim, PS modules)' `
            -Force -ErrorAction Stop | Out-Null
        Write-Host "✓ scheduled task '$script:MaintTaskName' installed for $When" -ForegroundColor Green
        Write-Host '  (StartWhenAvailable: catches up if the machine was off at that time)' -ForegroundColor DarkGray
        Write-Host '  winget upgrades are OFF by default — to include them, edit the task to set' -ForegroundColor DarkGray
        Write-Host '  the MAINT_WINGET_UPGRADE=1 environment variable, or run maint manually with it set.' -ForegroundColor DarkGray
    } catch {
        Write-Error "maint-install failed: $_"
    }
}

function maint-run {
    $maintScript = Get-MaintRunnerPath
    if (-not $maintScript) { return }
    $pwshPath = Get-PwshPath
    if (-not $pwshPath) { return }

    Write-Host "running $maintScript ..." -ForegroundColor Cyan
    & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $maintScript
}

function maint-log {
    param($Arg = 50)

    if (-not (Test-Path $script:MaintLog)) { Write-Host "no log yet at $script:MaintLog"; return }

    if ("$Arg" -in $script:FollowArgs) {
        Write-Host "following $script:MaintLog  (Ctrl-C to stop)" -ForegroundColor DarkGray
        try { Get-Content $script:MaintLog -Wait -Tail 20 }
        finally { Write-Host "`nstopped following the log." -ForegroundColor DarkGray }
    } else {
        $lineCount = 0
        if (-not [int]::TryParse("$Arg", [ref]$lineCount) -or $lineCount -le 0) {
            Write-Error 'usage: maint-log [N|-f]   (N must be a positive integer)'
            return
        }
        Get-Content $script:MaintLog -Tail $lineCount
    }
}

function maint-status {
    $task = Get-ScheduledTask -TaskName $script:MaintTaskName -ErrorAction SilentlyContinue
    if (-not $task) { Write-Host "not installed (run maint-install)"; return }
    $info = Get-ScheduledTaskInfo -TaskName $script:MaintTaskName
    [pscustomobject]@{
        Task        = $task.TaskName
        State       = $task.State
        NextRunTime = $info.NextRunTime
        LastRunTime = $info.LastRunTime
        LastResult  = ('0x{0:X}' -f $info.LastTaskResult)
    } | Format-List
}

function maint-uninstall {
    if (Get-ScheduledTask -TaskName $script:MaintTaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $script:MaintTaskName -Confirm:$false
        Write-Host "✓ removed scheduled task '$script:MaintTaskName'" -ForegroundColor Green
    } else {
        Write-Host "nothing to remove (task '$script:MaintTaskName' not found)" -ForegroundColor DarkYellow
    }
}
