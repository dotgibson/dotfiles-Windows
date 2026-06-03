# tmux-battery.ps1 — battery pill for the psmux status line.
# Windows-native port of core/tmux/scripts/tmux-battery.sh (standalone rewrite,
# invoked by psmux via #()).
#
# Prints a styled pill colored by charge level, with a charging glyph on AC.
# Emits NOTHING on a desktop with no battery, so the segment self-hides.
# Output to stdout, no trailing newline.
#
# Wired into psmux/.tmux.conf as:
#   #(pwsh -NoProfile -File ~/.tmux/scripts/tmux-battery.ps1)
#
# Note: the literal '%' lives in this script's OUTPUT, never in the .tmux.conf —
# same reason the bash version is a script: tmux runs strftime over status-right,
# which would mangle a '%' sitting in the conf, but it does not re-expand the
# embedded output of #(). Glyphs are `u{XXXX} escapes (named inline).

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# tokyonight-storm
$BG     = '#24283b'
$GREEN  = '#9ece6a'
$YELLOW = '#e0af68'
$RED    = '#f7768e'
$CAP_L  = "`u{e0b6}"   # e0b6 rounded left cap
$CAP_R  = "`u{e0b4}"   # e0b4 rounded right cap

$bat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bat) { return }   # no battery present -> emit nothing (segment vanishes)

$pct = [int]$bat.EstimatedChargeRemaining
# Win32_Battery.BatteryStatus: 1 = discharging, 2 = on AC, 6/7/8 = charging variants
$charging = $bat.BatteryStatus -in 2, 6, 7, 8

if     ($pct -ge 60) { $color = $GREEN;  $glyph = "`u{f240}" }   # f240 battery-full
elseif ($pct -ge 20) { $color = $YELLOW; $glyph = "`u{f242}" }   # f242 battery-half
else                 { $color = $RED;    $glyph = "`u{f244}" }   # f244 battery-empty
if ($charging)       { $glyph = "`u{f1e6}" }                     # f1e6 plug — charging

$out = "#[fg=$color,bg=default]$CAP_L#[fg=$BG,bg=$color,bold] $glyph $pct% #[fg=$color,bg=default]$CAP_R"
[Console]::Out.Write($out)
