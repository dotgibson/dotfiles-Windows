# psmux-netspeed.ps1 — network throughput segment of the status line.
# ──────────────────────────────────────────────────────────────────────────────
# Emits a fully-styled psmux "pill" showing current down/up throughput, summed
# across all up adapters. Wired up via a #() shell-out in psmux.conf:
#   #(pwsh -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.config\psmux\scripts\psmux-netspeed.ps1)
#
# Rate needs two samples over time. Rather than sleeping ~1s inside the bar (which
# would stall every refresh), each run reads the cumulative byte counters, then
# diffs them against the PREVIOUS run's counters + timestamp persisted in a small
# state file under $env:TEMP. So the rate is "bytes since the last status refresh
# / seconds since then" — which is exactly status-interval. First run shows 0.
#
# Deliberately tolerant (SilentlyContinue): a status helper must never hard-fail.
# ──────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = 'SilentlyContinue'

# tokyonight-storm palette. Literal hex (psmux does not expand #{@tn_*} here).
$BG   = '#292e42'
$BLUE = '#7aa2f7'

# left/right rounded caps (Nerd Font) — same glyphs as @cap_l / @cap_r
$CAP_L = ''
$CAP_R = ''

function Pill {
    param([string]$Accent, [string]$Text)
    "#[fg=$Accent,bg=$BG]$CAP_L#[fg=$BG,bg=$Accent,bold]$Text#[fg=$Accent,bg=$BG]$CAP_R"
}

# Cumulative byte counters across every adapter that currently has stats.
$stats = Get-NetAdapterStatistics -ErrorAction SilentlyContinue
if (-not $stats) { return }
$rx  = [double](($stats | Measure-Object -Property ReceivedBytes -Sum).Sum)
$tx  = [double](($stats | Measure-Object -Property SentBytes     -Sum).Sum)
$now = [double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# Diff against the previous sample (rx, tx, epoch-ms) persisted last run.
$state    = Join-Path $env:TEMP 'psmux-netspeed.state'
$downRate = 0.0
$upRate   = 0.0
$prev = Get-Content $state -ErrorAction SilentlyContinue
if ($prev -and $prev.Count -ge 3) {
    $pRx = [double]$prev[0]; $pTx = [double]$prev[1]; $pT = [double]$prev[2]
    $dt  = ($now - $pT) / 1000.0
    # Guard against the counter resetting (adapter bounce) producing a negative.
    if ($dt -gt 0) {
        if ($rx -ge $pRx) { $downRate = ($rx - $pRx) / $dt }
        if ($tx -ge $pTx) { $upRate   = ($tx - $pTx) / $dt }
    }
}
Set-Content -Path $state -Value @($rx, $tx, $now) -ErrorAction SilentlyContinue

# Compact human rate: B / K / M per second.
function Fmt([double]$bps) {
    if     ($bps -ge 1048576) { '{0:N1}M' -f ($bps / 1048576) }
    elseif ($bps -ge 1024)    { '{0:N0}K' -f ($bps / 1024) }
    else                      { '{0:N0}B' -f $bps }
}

#  = nf-md-download (U+F01DA),  = nf-md-upload (U+F0552). Swap if your font lacks them.
Pill $BLUE (" {0}  {1}" -f (Fmt $downRate), (Fmt $upRate))
