# ============================================================================
#  core/15-update.ps1  -  "tell me when there are updates, don't make me check"
#
#  Windows port of Core's zsh/update.zsh. Same philosophy:
#    • a throttled (once/day), BACKGROUNDED check on shell start that prints a
#      single one-line nudge if packages are upgradable, then
#    • APPLYING is your call via `up` (or the scheduled maint job, os/40-maint.ps1).
#
#  Unlike the Linux boxes this never needs elevation — scoop and winget both
#  install/upgrade in user space. The check is best-effort: anything ambiguous
#  (offline, weird output) yields a silent no-op, exactly like the zsh version.
#
#  Config (override in local.ps1, BEFORE this loads if you set the env var):
#    $env:DOTFILES_UPDATE_CHECK = '0'   # disable the startup nudge entirely
# ============================================================================

$script:PkgUpCache          = Join-Path $env:LOCALAPPDATA 'dotfiles\pkg-updates'
$script:UpdateCheckInterval = 86400   # seconds between background checks
if (-not $env:DOTFILES_UPDATE_CHECK) { $env:DOTFILES_UPDATE_CHECK = '1' }

# --- the one-line nudge (instant; reads the cache, does no work) --------------
function script:Show-PkgUpdateNotice {
    if (-not (Test-Path $script:PkgUpCache)) { return }
    $count = (Get-Content $script:PkgUpCache -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($count -match '^\d+$' -and [int]$count -gt 0) {
        $c = [int]$count
        $s = if ($c -ne 1) { 's' } else { '' }
        Write-Host ("`u{f069a} {0} update{1} available" -f $c, $s) -ForegroundColor Blue -NoNewline
        Write-Host "  - run 'up' to apply" -ForegroundColor DarkGray
    }
}

# --- force a synchronous refresh, then nudge: `update-check` ------------------
function update-check {
    $dir = Split-Path -Parent $script:PkgUpCache
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $n = (& $script:PkgUpCountSb)
    Set-Content -Path $script:PkgUpCache -Encoding ascii `
        -Value @("$n", "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
    Show-PkgUpdateNotice
}

# --- the counter, kept as a scriptblock so the background job can reuse it ----
# Best-effort, NON-elevating count across scoop + winget. -1 == "unknown/offline".
$script:PkgUpCountSb = {
    $count = 0; $sawAny = $false

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        $sawAny = $true
        try {
            scoop update *> $null                 # refresh manifests (buckets); NOT an app upgrade
            $status = scoop status 6> $null 2> $null
            $n = ($status | Where-Object {
                    $_ -match '\S' -and
                    $_ -notmatch '^(Name|----|Scoop|WARN|Everything|Updates|$)'
                } | Measure-Object).Count
            if ($n -ge 0) { $count += $n }
        } catch { }
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $sawAny = $true
        try {
            $wg  = winget upgrade --include-unknown 2> $null
            $sep = $wg | Select-String -Pattern '^-{3,}' | Select-Object -First 1
            if ($sep) {
                $idx  = [array]::IndexOf([string[]]$wg, $sep.Line)
                $rows = $wg[($idx + 1)..($wg.Count - 1)] | Where-Object {
                    $_ -match '\S' -and
                    $_ -notmatch 'upgrades? available|No installed package|package\(s\) have'
                }
                $count += ($rows | Measure-Object).Count
            }
        } catch { }
    }

    if (-not $sawAny) { return -1 }
    return $count
}

# --- startup hook: throttle + background the check, then show cached nudge ----
if ($env:DOTFILES_UPDATE_CHECK -eq '1' -and
    ((Get-Command scoop -ErrorAction SilentlyContinue) -or
     (Get-Command winget -ErrorAction SilentlyContinue))) {

    $now  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $last = 0
    if (Test-Path $script:PkgUpCache) {
        $stamp = (Get-Content $script:PkgUpCache -ErrorAction SilentlyContinue | Select-Object -Skip 1 -First 1)
        if ($stamp -match '^\d+$') { $last = [int64]$stamp }
    }

    if (($now - $last) -ge $script:UpdateCheckInterval) {
        # Claim the slot immediately (bump the timestamp) so sibling shells opened
        # in the same instant don't all fire, then refresh in a background job.
        $dir = Split-Path -Parent $script:PkgUpCache
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $prev = if (Test-Path $script:PkgUpCache) {
            (Get-Content $script:PkgUpCache -ErrorAction SilentlyContinue | Select-Object -First 1)
        } else { '-1' }
        Set-Content -Path $script:PkgUpCache -Encoding ascii -Value @("$prev", "$now")

        Start-Job -ScriptBlock {
            param($cache, $counter)
            $n = (& ([scriptblock]::Create($counter)))
            Set-Content -Path $cache -Encoding ascii `
                -Value @("$n", "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
        } -ArgumentList $script:PkgUpCache, $script:PkgUpCountSb.ToString() | Out-Null
    }

    Show-PkgUpdateNotice
}

# ============================================================================
#  up — apply updates. The fleet-standard verb (matches zsh `up`). scoop+winget
#  are user-space, so no elevation. `up -y` auto-confirms winget; scoop is always
#  non-interactive. Refreshes the nudge cache afterward so the notice clears.
#    up        # review (winget shows prompts)
#    up -y     # auto-confirm winget upgrades
# ============================================================================
function up {
    [CmdletBinding()] param([switch]$y)

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host '== scoop ==' -ForegroundColor Cyan
        scoop update
        scoop update *
        scoop cleanup *
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host '== winget ==' -ForegroundColor Cyan
        $wargs = @('upgrade', '--all', '--include-unknown')
        if ($y) { $wargs += @('--silent', '--accept-package-agreements', '--accept-source-agreements') }
        winget @wargs
    }
    update-check | Out-Null      # clear the nudge
    Write-Host 'done.' -ForegroundColor Green
}

