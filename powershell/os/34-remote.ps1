# ============================================================================
#  os/34-remote.ps1  -  the client-side ssh_config for the distros behind this host.
#
#  The host-side twin of 31-wsl-bridge: that fragment is for reaching a distro
#  from a shell you already have on this box, this one is for the machine coming
#  IN over ssh, which needs a Host entry per distro and a port that does not move.
#
#    wsl-ssh-config           the ssh_config block for every installed distro
#
#  It PRINTS and never writes. The output belongs in the ~/.ssh/config of the
#  machine you ssh FROM, which by definition is not this one — so writing it
#  here would put it on the wrong box.
#
#    remote-status            what the host sshd is, and what it is missing
#    remote-install           register it as a service that restarts itself, and
#                             point DefaultShell at a shell that survives an update
#
#  Those two NARROW an older decision rather than reversing it. The rule was that
#  standing sshd up — the service, the firewall rules, the HKLM DefaultShell key,
#  the boot task, the power settings — is machine-global state that varies per box
#  and therefore belongs in a runbook (docs/REMOTE-ACCESS.md), not in this repo.
#  Most of that still holds and is still absent here.
#
#  What did not survive contact with a real host is leaving SUPERVISION to the
#  runbook. Done by hand, this box ended up with a bare sshd.exe that nothing
#  restarted: no service, no task (verified by reading every task XML under
#  System32\Tasks, not just what Get-ScheduledTask shows unelevated), so every
#  crash and every reboot needed a human, repeatedly, for months. A runbook step
#  that has to be re-done by hand after each failure is not a runbook step.
#
#  So supervision — and only supervision — moves in here, in the shape maint-install
#  already established for scheduled tasks: typed on purpose, never implicit, refusing
#  without an admin token rather than half-applying. Ports, keys and firewall rules
#  stay in the runbook where they belong.
#
#  Layer boundary: everything here is HOST side. Enabling sshd inside a distro,
#  and the port it listens on, belong to that distro's own repo (dotfiles-Debian
#  for the Kali/Debian/Ubuntu family) — this fragment only decides which host
#  port each distro answers on, and gets out of the way.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: Get-WslDistroNames, wsl-ssh-config, remote-status, remote-install
# requires: Format-DotWslSshConfig, Get-DotSshdServicePlan, Get-DotSshdShellVerdict, Get-DotWslSshPlan, Test-Cmd, Write-DotErr, Write-DotHost, Write-DotOk, Write-DotWarn, hostip

# --- the installed distros ----------------------------------------------------
# `wsl --list --quiet` emits UTF-16LE by default, which lands in PowerShell as a
# string with a NUL between every character — the single most common reason a
# script that shells out to wsl "sees" no distros. WSL_UTF8=1 makes it emit UTF-8
# (recent WSL builds); the NUL strip is the belt for the ones that don't honour
# it. Set on the CHILD only, so nothing else in the session inherits it, and
# restored in finally — including the unset case, which must be REMOVED rather
# than set to empty or the next caller inherits a variable that was never there.
function Get-WslDistroNames {
    if (-not (Test-Cmd wsl)) { return @() }
    $prev = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try { $raw = & wsl.exe --list --quiet 2>$null }
    catch { return @() }
    finally {
        if ($null -eq $prev) { Remove-Item Env:WSL_UTF8 -ErrorAction SilentlyContinue }
        else { $env:WSL_UTF8 = $prev }
    }
    return @($raw |
        ForEach-Object { ($_ -replace "`0", '').Trim() } |
        Where-Object { $_ })
}

# --- the client-side ssh_config block -----------------------------------------
# Print the Host entries for every installed distro, for pasting into the
# ~/.ssh/config of the machine you ssh FROM. -JumpHost routes them through the
# Windows host's own sshd instead of exposing a LAN port per distro, which is the
# shape to prefer for anything reachable from outside the house.
function wsl-ssh-config {
    param(
        [string]$JumpHost,
        [int]$BasePort = 2222,
        # The port the WINDOWS sshd answers on. Passed through so the allocator can
        # refuse to hand that port to a distro: a host that moved sshd off 22 is
        # common, and assuming 22 hands out a collision the plan cannot see.
        [int]$HostPort = 22,
        [string]$User
    )
    $names = Get-WslDistroNames
    if (-not $names.Count) { Write-DotErr 'no WSL distros found' 'wsl --list --verbose'; return }

    $plan = Get-DotWslSshPlan -Distro $names -BasePort $BasePort -HostPort $HostPort -User $User
    # Without a jump host the distro ports have to be dialled at this box's LAN
    # address; hostip comes from 31-wsl-bridge, which returns early on a host with
    # no wsl — guarded so a degraded load prints a placeholder instead of throwing.
    $addr = if ($JumpHost) { '127.0.0.1' }
            elseif (Get-Command hostip -ErrorAction SilentlyContinue) { hostip }
            else { '<host-ip>' }
    if (-not $addr) { $addr = '<host-ip>' }

    Write-DotHost (Format-DotWslSshConfig -Plan $plan -HostName $addr -Jump $JumpHost)
    Write-DotHost ''
    Write-DotHost 'Each distro must listen on its mapped port — set it in that distro''s own repo' -Color DarkGray
    Write-DotHost '(Port <n> in /etc/ssh/sshd_config, then: sudo systemctl enable --now ssh).' -Color DarkGray
}

# --- the host sshd, as a service that restarts itself -------------------------
# The host reads live here and the policy lives in Get-DotSshdServicePlan, the
# same split as maint-install / Get-DotStablePwshPath.
#
# Nothing below runs implicitly. Both verbs are typed on purpose, remote-status
# only reads, and remote-install refuses without a token rather than half-applying
# — which keeps this inside the repo's "no machine-global state behind your back"
# rule while still making the front door reproducible.

# Every sshd.exe worth registering, MOST PREFERRED FIRST. The scoop `current`
# junction beats its own resolved target: a version-pinned ImagePath dies on the
# next `scoop update openssh` and takes the front door with it, silently.
function script:Get-DotSshdCandidate {
    $scoopCurrent = Join-Path $HOME 'scoop\apps\openssh\current\sshd.exe'
    $rows = @(
        @{ Path = $scoopCurrent; Kind = 'scoop current'; VersionPinned = $false }
        @{ Path = (Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'); Kind = 'windows feature'; VersionPinned = $false }
    )
    # The resolved target, last, as the fallback for a box whose junction is gone.
    try {
        $target = (Get-Item (Split-Path $scoopCurrent -Parent) -ErrorAction Stop).Target
        if ($target) { $rows += @{ Path = (Join-Path $target 'sshd.exe'); Kind = 'scoop versioned'; VersionPinned = $true } }
    } catch { }

    foreach ($r in $rows) {
        [pscustomobject]@{
            Path = $r.Path; Kind = $r.Kind; VersionPinned = $r.VersionPinned
            Exists = (Test-Path -LiteralPath $r.Path -ErrorAction SilentlyContinue)
        }
    }
}

# The host reads the planner judges. Kept together so remote-status and
# remote-install cannot drift into asking different questions.
function script:Get-DotSshdPlan {
    $svc = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue

    # Registration does NOT imply recovery actions — scoop's install-sshd.ps1
    # leaves the default "take no action", which is the whole bug this guards.
    $recovery = $false
    if ($svc) {
        $q = (& sc.exe qfailure sshd 2>&1 | Out-String)
        $recovery = $q -match '(?im)^\s*RESTART'
    }

    $held = $false
    try {
        $j = Join-Path $HOME 'scoop\apps\openssh\current\install.json'
        if (Test-Path $j) { $held = [bool]((Get-Content $j -Raw | ConvertFrom-Json).hold) }
    } catch { }

    Get-DotSshdServicePlan `
        -Candidate @(Get-DotSshdCandidate) `
        -Registered ([bool]$svc) `
        -ImagePath  ([string]$svc.PathName) `
        -StartType  $(switch ([string]$svc.StartMode) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { '' } }) `
        -State      $(if ($svc.State -in 'Running', 'Stopped') { [string]$svc.State } else { '' }) `
        -RecoveryConfigured $recovery `
        -IsElevated (Test-DotAdmin) `
        -PackageHeld $held
}

function script:Test-DotAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The three registry/filesystem reads behind Get-DotSshdShellVerdict. HKLM's
# OpenSSH key is world-readable, so status works from any shell.
function script:Get-DotSshdShellState {
    $value = ''
    try { $value = [string](Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction Stop).DefaultShell } catch { }

    $exists  = $false
    $reparse = $false
    if ($value) {
        $exists = Test-Path -LiteralPath $value -ErrorAction SilentlyContinue
        if ($exists) {
            try {
                $attrs   = (Get-Item -LiteralPath $value -Force -ErrorAction Stop).Attributes
                $reparse = ($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0
            } catch { }
        }
    }
    Get-DotSshdShellVerdict -Path $value -Exists $exists -IsReparsePoint $reparse
}

# A shell sshd can still launch after the next PowerShell update, MOST PREFERRED
# FIRST. Machine-wide real files only: the per-user app alias is version-stable but
# a reparse point, which sshd cannot traverse — see Get-DotSshdShellVerdict.
function script:Get-DotSshdShellCandidate {
    @(
        @{ Path = 'C:\Program Files\PowerShell\7\pwsh.exe';                    Kind = 'pwsh 7 (MSI)' }
        @{ Path = 'C:\Program Files\PowerShell\7-preview\pwsh.exe';            Kind = 'pwsh 7 preview (MSI)' }
        @{ Path = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'); Kind = 'Windows PowerShell 5.1' }
    ) | ForEach-Object {
        $exists  = Test-Path -LiteralPath $_.Path -ErrorAction SilentlyContinue
        $reparse = $false
        if ($exists) {
            try { $reparse = ((Get-Item -LiteralPath $_.Path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } catch { }
        }
        [pscustomobject]@{ Path = $_.Path; Kind = $_.Kind; Exists = $exists; IsReparsePoint = $reparse }
    }
}

# Report what the front door is, without touching anything.
function remote-status {
    $plan = Get-DotSshdPlan
    Write-DotHost 'host sshd' -Color Cyan

    switch ($plan.Action) {
        'no-binary' { Write-DotErr 'no sshd.exe found' 'scoop install openssh'; return }
        'ok'        { Write-DotOk  "  service healthy — $($plan.Path)" }
        'blocked'   {
            Write-DotWarn "  needs work, but this shell has no admin token: $($plan.Steps -join ', ')" `
                'run `admin`, then remote-install'
        }
        default     { Write-DotWarn "  $($plan.Reason)" 'run `admin`, then remote-install' }
    }
    foreach ($w in $plan.Warnings) { Write-DotWarn "  $w" }

    # Reported separately from the service because it fails separately, and far more
    # confusingly: a perfectly healthy service still refuses every login when this is
    # wrong, and tells the client only "Permission denied (publickey,...)".
    $shell = Get-DotSshdShellState
    switch ($shell.Status) {
        'ok'     { Write-DotOk   "  login shell — $($shell.Path)" }
        'unset'  { Write-DotHost "  login shell — $($shell.Detail)" -Color DarkGray }
        default  { Write-DotWarn "  login shell $($shell.Status.ToUpperInvariant()): $($shell.Path)`n     $($shell.Detail)" $shell.Hint }
    }
}

# Make the front door survive a crash and a reboot. Elevated, explicit, idempotent.
function remote-install {
    param([switch]$DryRun)

    $plan = Get-DotSshdPlan
    Write-DotHost "sshd plan: $($plan.Reason)" -Color Cyan
    if ($plan.Path) { Write-DotHost "  binary: $($plan.Path)" -Color DarkGray }
    foreach ($w in $plan.Warnings) { Write-DotWarn "  $w" }

    $shell = Get-DotSshdShellState
    if ($shell.NeedsFix) { Write-DotWarn "  login shell $($shell.Status): $($shell.Detail)" }

    if ($plan.Action -eq 'no-binary') { Write-DotErr 'no sshd.exe found' 'scoop install openssh'; return }
    if ($plan.Action -eq 'blocked')   {
        Write-DotErr 'remote-install needs an elevated shell' 'run `admin`, then re-run remote-install'
        return
    }
    # NOT an early return when the service is 'ok': DefaultShell fails on its own
    # terms, and a healthy service with a dead shell refuses every login while
    # looking perfect. That combination is exactly what locked this host out.
    if ($plan.Action -eq 'ok' -and -not $shell.NeedsFix) {
        Write-DotOk 'nothing to do — sshd is already self-healing'
        return
    }
    if ($DryRun) {
        if ($plan.Steps.Count) { Write-DotHost "  would run: $($plan.Steps -join ', ')" -Color DarkGray }
        if ($shell.NeedsFix)   { Write-DotHost '  would repoint DefaultShell at a version-stable shell' -Color DarkGray }
        return
    }

    foreach ($step in $plan.Steps) {
        try {
            switch ($step) {
                'register' {
                    # Prefer scoop's own installer: it also registers the event-log
                    # manifest and the sshd/ssh-agent pair, which a bare sc.exe create
                    # would leave out.
                    $installer = Join-Path (Split-Path $plan.Path -Parent) 'install-sshd.ps1'
                    if (Test-Path $installer) { & $installer | Out-Null }
                    else { & sc.exe create sshd binPath= "`"$($plan.Path)`"" start= auto | Out-Null }
                    Write-DotOk '  registered sshd'
                }
                'reregister-imagepath' {
                    & sc.exe config sshd binPath= "`"$($plan.Path)`"" | Out-Null
                    Write-DotOk "  ImagePath -> $($plan.Path)"
                }
                'set-automatic' {
                    Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
                    Write-DotOk '  start type -> Automatic'
                }
                'set-recovery' {
                    # The self-healing itself: restart after 5s, then 10s, then 30s,
                    # with the failure count reset daily so a slow drip of crashes
                    # never exhausts the actions and leaves it down for good.
                    & sc.exe failure sshd reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
                    & sc.exe failureflag sshd 1 | Out-Null
                    Write-DotOk '  recovery -> restart 5s / 10s / 30s, reset daily'
                }
                'start' {
                    Start-Service -Name sshd -ErrorAction Stop
                    Write-DotOk '  started'
                }
            }
        } catch {
            Write-DotErr "  step '$step' failed: $_"
            return
        }
    }

    if ($shell.NeedsFix) {
        $pick = @(Get-DotSshdShellCandidate | Where-Object { $_.Exists -and -not $_.IsReparsePoint })[0]
        if (-not $pick) {
            Write-DotErr '  no version-stable shell found to point DefaultShell at' `
                'install the MSI PowerShell: msiexec /i https://github.com/PowerShell/PowerShell/releases/latest'
        } else {
            try {
                Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $pick.Path -ErrorAction Stop
                Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShellCommandOption -Value '-Command' -ErrorAction Stop
                Write-DotOk "  DefaultShell -> $($pick.Path)  [$($pick.Kind)]"
                if ($pick.Kind -like 'Windows PowerShell*') {
                    Write-DotWarn '  that is Windows PowerShell 5.1, not pwsh 7 — ssh works but your profile will not load.' `
                        'install the MSI pwsh build, then re-run remote-install'
                }
            } catch {
                Write-DotErr "  DefaultShell could not be set: $_"
            }
        }
    }

    Write-DotHost ''
    remote-status
}
