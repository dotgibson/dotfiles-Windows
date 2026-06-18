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

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: update-check, up
# requires: Get-DotGlyph, Write-DotBanner, Write-DotHost, Write-DotOk, Write-DotWarn

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
        # Glyph + colour route through the shared helpers so the nudge degrades on
        # NO_COLOR (no ANSI) and DOTFILES_ASCII / legacy codepages (no tofu) like
        # the rest of the output, instead of emitting a raw nerd-font codepoint.
        $g = Get-DotGlyph pkg
        Write-DotHost ("{0} {1} update{2} available" -f $g, $c, $s) -Color Blue -NoNewline
        Write-DotHost "  - run 'up' to apply" -Color DarkGray
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
# FAST_START suppresses the startup nudge and background spawn (but `up` /
# `update-check` are still defined below, so a fast shell can apply on demand).
if ($env:FAST_START -ne '1' -and
    $env:DOTFILES_UPDATE_CHECK -eq '1' -and
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

        # Prefer Start-ThreadJob (ships with pwsh 7): it runs the check on a thread
        # in THIS process instead of spawning a whole child pwsh, so the shell-start
        # cost of the once-a-day refresh is far lower. Fall back to Start-Job on any
        # host without the ThreadJob module.
        $bg = {
            param($cache, $counter)
            $n = (& ([scriptblock]::Create($counter)))
            Set-Content -Path $cache -Encoding ascii `
                -Value @("$n", "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
        }
        $bgArgs = @($script:PkgUpCache, $script:PkgUpCountSb.ToString())
        if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
            Start-ThreadJob -ScriptBlock $bg -ArgumentList $bgArgs | Out-Null
        } else {
            Start-Job -ScriptBlock $bg -ArgumentList $bgArgs | Out-Null
        }
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
    [CmdletBinding()] param([switch]$y, [Alias('n')][switch]$Preview)

    # Preview (`up -Preview` / `up -n`): list what WOULD upgrade and apply nothing,
    # so the daily upgrade verb isn't a leap of faith. Mirrors install.ps1 -DryRun.
    if ($Preview) {
        Write-DotBanner 'pending updates' -Subtitle 'preview — nothing will be changed'
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Host ''; Write-DotHost '== scoop ==' -Color Cyan
            scoop status
        }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host ''; Write-DotHost '== winget ==' -Color Cyan
            winget upgrade --include-unknown
        }
        Write-Host ''
        Write-DotHost "  run 'up' to apply (winget prompts per package), or 'up -y' to auto-confirm." -Color DarkGray
        return
    }

    # Wrap the apply so a Ctrl-C mid-upgrade acknowledges itself and still refreshes
    # the nudge cache, instead of dropping you at a bare prompt with a half-applied
    # batch (U12: parity with install.ps1 / Install-Packages.ps1).
    $done = $false
    try {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-DotHost '== scoop ==' -Color Cyan
            scoop update
            scoop update *
            scoop cleanup *
        }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-DotHost '== winget ==' -Color Cyan
            $wargs = @('upgrade', '--all', '--include-unknown')
            if ($y) { $wargs += @('--silent', '--accept-package-agreements', '--accept-source-agreements') }
            winget @wargs
        }
        $done = $true
    } finally {
        update-check | Out-Null      # refresh the nudge either way (clears on success)
        if ($done) { Write-DotOk 'done.' }
        else { Write-DotWarn 'update interrupted — re-run `up` to finish (already-current packages are skipped).' }
    }
}

