# psmux-cpu.ps1 — CPU-load segment of the status line.
# ──────────────────────────────────────────────────────────────────────────────
# Emits a fully-styled psmux "pill" (its own #[...] colour codes) showing total
# CPU utilisation, colour-coded by load: green < 50%, yellow < 85%, red above.
# Wired up via a #() shell-out in psmux.conf:
#   #(pwsh -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.config\psmux\scripts\psmux-cpu.ps1)
# psmux caches #() output for `status-interval` seconds, so this runs at most
# once per refresh. Uses the Win32_PerfFormattedData CIM class (instantaneous,
# locale-independent, no 1s Get-Counter sample), so it never blocks the bar.
#
# Deliberately tolerant (SilentlyContinue): a status helper must never hard-fail.
# ──────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = 'SilentlyContinue'

# tokyonight-storm palette. Literal hex on purpose: psmux does not expand #{@tn_*}
# inside #[...] (in #() output any more than in style options). BG = the bar's
# highlight bg (@tn_bg_hl) so the pill floats like the cwd / clock pills.
$BG     = '#292e42'
$GREEN  = '#9ece6a'
$YELLOW = '#e0af68'
$RED    = '#f7768e'

# left/right rounded caps (Nerd Font) — same glyphs as @cap_l / @cap_r
$CAP_L = ''
$CAP_R = ''

function Pill {
    param([string]$Accent, [string]$Text)
    "#[fg=$Accent,bg=$BG]$CAP_L#[fg=$BG,bg=$Accent,bold]$Text#[fg=$Accent,bg=$BG]$CAP_R"
}

# Total CPU %, instantaneous. _Total is the rollup across all logical CPUs.
$cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue).PercentProcessorTime
if ($null -eq $cpu) { return }   # no pill if the counter is unavailable
$cpu = [int]$cpu

$accent = if ($cpu -ge 85) { $RED } elseif ($cpu -ge 50) { $YELLOW } else { $GREEN }

#  = nf-md-cpu_64_bit (U+F0EE0). Swap the glyph if your Nerd Font lacks it.
Pill $accent (" {0,3}%" -f $cpu)
