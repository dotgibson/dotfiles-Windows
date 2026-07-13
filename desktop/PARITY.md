<!-- ============================================================================
     KEEP IN SYNC: an identical copy of this file lives in BOTH repos —
     dotfiles-MacBook/sketchybar/PARITY.md and dotfiles-Windows/desktop/PARITY.md. Edit both together — it is the single
     shared contract that keeps the Zebar (Windows) and sketchybar (macOS) bars
     looking and behaving the same. When you change one bar, update this spec and
     mirror it to the other repo.
     ============================================================================ -->

# Bar parity contract — Zebar ↔ sketchybar

Two bars, two hosts, one design: **Zebar** on the Windows/GlazeWM host
(`dotfiles-Windows/desktop/zebar/vanilla-clear/`, buildless React/HTML/CSS) and
**sketchybar** on the macOS/AeroSpace host (`dotfiles-MacBook/sketchybar/`, bash +
`sketchybar` CLI). Different tech, deliberately identical result. This file is the
canonical spec; both implementations follow it.

## Layout (identical, left → center → right)

| Zone | Modules (in order) |
| --- | --- |
| **Left** | `logo` · `workspaces` · *(binding-mode — Windows only)* · `front_app` · `pomodoro` |
| **Center** | `clock` |
| **Right** | `network` · `volume` · `disk` · `memory` · `cpu` · `battery` · `weather` · *(caffeinate — macOS only)* · `power` |

Two sanctioned platform exceptions (no cross-platform equivalent):

- **binding-mode** — GlazeWM binding modes (e.g. `resize`); shown after
  `workspaces` only while a mode is active. AeroSpace has no equivalent.
- **caffeinate / keep-awake** — macOS `caffeinate -di` toggle, far right before
  `power`. No matching one-shot toggle on the Windows host.

`logo` is a per-host brand glyph: Apple `` (macOS) / Windows `` (nf-fa-windows).
`clock` uses the format `EEE d MMM t` → e.g. `Mon 13 Jul 2:45 PM`.

## Geometry (floating rounded, matched proportions)

| Token | Value |
| --- | --- |
| Bar background | `#1d202f` @ ~93% alpha — `0xee1d202f` (sketchybar) / `rgba(29,32,47,0.93)` (Zebar) |
| Outer float gap | 8px |
| Bar corner radius | 9px |
| Workspace container radius | 8px |
| Blur | on |

Individual items are **chip-less** — plain spaced icon+text directly on the
translucent bar (no per-item background). The only rounded container is the
`workspaces` group.

- **sketchybar** floats natively: `--bar height=20 margin=8 corner_radius=9 blur_radius=20`.
- **Zebar** floats via CSS: the transparent full-width window paints an inset
  rounded pill (`.app { margin: 8px; border-radius: 9px; background: <token> }`).
  GlazeWM's existing `gaps.outer.top: 50px` already clears it.

## Font

**CaskaydiaCove Nerd Font** on both (macOS: Homebrew cask; Windows: the
`CascadiaCode-NF` scoop package installs this exact family). Sizes are matched
visually, not pixel-identical across DPI: sketchybar `14.0` pt, Zebar `13px`.

The two variable-width labels — **front-app** and the **now-playing** title —
are capped at ~22 chars on both bars (Zebar: `max-width: 22ch` + ellipsis;
sketchybar: `label.max_chars=22`) so a long app name or song title can't grow into
the centered clock.

## Colors — semantic load scheme (Tokyo Night Storm)

| Token | Hex | `0xAARRGGBB` | Role |
| --- | --- | --- | --- |
| bg | `#24283b` | `0xff24283b` | item background |
| fg | `#c0caf5` | `0xffc0caf5` | default text |
| fg-dim | `#a9b1d6` | — | dimmed text (workspaces, power btns) |
| blue / accent | `#7aa2f7` | `0xff7aa2f7` | active highlight, logo, workspaces, front_app, network, clock, weather, battery-charging |
| green | `#9ece6a` | `0xff9ece6a` | load: low |
| yellow | `#e0af68` | `0xffe0af68` | load: mid |
| red | `#f7768e` | `0xfff7768e` | load: high |
| cyan | `#7dcfff` | `0xff7dcfff` | volume |
| purple | `#bb9af7` | `0xffbb9af7` | reserved (Tokyo Night accent; currently unused) |
| grey / comment | `#565f89` | `0xff565f89` | inactive / dim |

Shared thresholds (glyph **and** value colored together):

| Module | low (green) | mid (yellow) | high (red) |
| --- | --- | --- | --- |
| cpu | 0–49 | 50–79 | 80+ |
| memory | <70 | 70–87 | 88+ |
| disk (used %) | <80 (fg) | 80–89 | 90+ |
| battery (charge %) | >40 | 21–40 | ≤20 |

`network` = blue. `volume` = cyan. `workspaces` focused = blue pill with dark text.

## Glyphs (one nerd-font icon per module, used verbatim by both)

sketchybar embeds the literal glyph; Zebar uses the matching `nf-*` class from the
Nerd Fonts webfont. Same icon on both.

| Module | Nerd Font name | glyph | Zebar `nf-*` class |
| --- | --- | --- | --- |
| logo (macOS) | fa-apple |  | — |
| logo (Windows) | fa-windows |  | `nf-fa-windows` |
| pomodoro | md-timer-outline | 󰔛 | `nf-md-timer_outline` |
| clock | md-clock-outline | 󰅐 | `nf-md-clock_outline` |
| network | md-speedometer | 󰓅 | `nf-md-speedometer` |
| volume high/med/low/off | md-volume-high / medium / low / off | 󰕾 󰖀 󰕿 󰖁 | `nf-md-volume_high` / `_medium` / `_low` / `_off` |
| disk | md-harddisk | 󰋊 | `nf-md-harddisk` |
| memory | md-memory | 󰍛 | `nf-md-memory` |
| cpu | md-cpu-64-bit | 󰻠 | `nf-md-cpu_64_bit` |
| battery full/¾/½/¼/empty | fa-battery-4/3/2/1/0 |      | `nf-fa-battery_4` … `_0` |
| battery charging bolt | md-power-plug | 󰚥 | `nf-md-power_plug` |
| weather | weather-\* (day/night × clear/cloudy/rain/snow/thunder) | see weather.sh / getWeatherIcon | `nf-weather-*` |
| caffeinate awake/asleep | md-coffee / md-power-sleep | 󰅶 󰒲 | — |
| power | md-power | 󰐥 | `nf-md-power` |
| power → lock/sleep/restart/shutdown | md-lock / power-sleep / restart / power | 󰌾 󰤄 󰜉 󰐥 | `nf-md-lock` / `nf-md-power_sleep` / `nf-md-restart` / `nf-md-power` |

## Behaviour parity

- **network** — throughput `↓<down> ↑<up>`, compact units (`B`/`K`/`M` per second).
- **pomodoro** — 25/5 work-break timer; left-click start/pause, right-click reset;
  states colored green (work) / blue (break) / grey (paused).
- **power** — collapsed icon expands to lock · sleep · restart · shutdown.
- **clock + battery** also appear here even though the macOS tmux status bar shows
  them too — a deliberate choice for cross-host parity.
