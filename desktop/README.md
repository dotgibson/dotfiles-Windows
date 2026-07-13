# desktop/ — the opt-in tiling-desktop layer

Everything under `desktop/` is **optional**. The rest of `dotfiles-Windows` makes
the *shell host* excellent (PowerShell, Windows Terminal, scoop/winget, psmux) and
otherwise stays out of the way. This layer is for when you also want the *desktop*
tiled and themed — a Linux-rice feel on the Windows host — adapted from
[Gerrrt/make-windows-pretty](https://github.com/Gerrrt/make-windows-pretty) and
retuned to the fleet's Tokyo Night Storm palette.

It ships three things: a **tiling window manager** (GlazeWM), a **top bar**
(Zebar), and two **quality-of-life apps** (PowerToys, TranslucentTB).

## What's here

| Path | What | Symlinked to |
| --- | --- | --- |
| `glazewm/config.yaml` | GlazeWM tiling-WM config (Tokyo Night, vim-key focus) | `~/.glzr/glazewm/config.yaml` |
| `zebar/vanilla-clear/` | Zebar v3 widget pack (`zpack.json`) — logo · workspaces · front-app · pomodoro \| clock \| media · net · volume · disk · mem · cpu · battery · weather · power (kept at parity with macOS sketchybar; see `PARITY.md`) | `~/.glzr/zebar/vanilla-clear` |

The symlinks are wired by `install.ps1` from the shared link plan
(`Get-DotfilesLinkPlan`), so `dotfiles-doctor` verifies them and `uninstall.ps1`
removes them — same as every other config in this repo.

## Install

The four apps live in the **`desktop` optional package group** in
`packages/winget.json`. They install by default; to opt out on a shell-only box,
deselect `desktop` at the first `Install-Packages.ps1` prompt, or set
`DOTFILES_PKG_GROUPS` in `powershell/local.ps1` (see `local.ps1.example`).

| App | winget id | Role |
| --- | --- | --- |
| GlazeWM | `glzr-io.glazewm` | tiling window manager |
| Zebar | `glzr-io.zebar` | top status bar |
| PowerToys | `Microsoft.PowerToys` | launcher (PowerToys Run), FancyZones, etc. |
| TranslucentTB | `CharlesMilette.TranslucentTB` | translucent taskbar |

The config files are linked regardless of the package selection (harmless if the
apps aren't installed), so opting in later is just a re-run of the package step.

## Manual steps (one-time, per the apps' own setup)

These aren't things a dotfile can do for you:

1. **Launch on login.** Add GlazeWM to startup (it launches Zebar via
   `startup_commands`). PowerToys and TranslucentTB each have their own
   "run at startup" toggle in-app.
2. **Enable the Zebar widget.** The `vanilla-clear` pack is a Zebar **v3 widget
   pack** (`zpack.json`); Zebar 3.x discovers it under `~/.glzr/zebar/`. Open Zebar,
   pick the `vanilla-clear` widget, and mark it to start (disable the bundled
   samples you don't want). GlazeWM's `startup_commands` runs `zebar`, which opens
   whatever you've marked as startup.
3. **PowerToys Run** defaults to `Alt+Space`. That does **not** collide with the
   GlazeWM binds here (which are `Alt`/`Alt+Shift` + letters/numbers).

## Keybindings (GlazeWM)

Retuned from upstream to **not** fight Windows Terminal. WT already uses
`Alt+<arrow>` for pane focus (`windows-terminal/settings.json`), so this config
drops the `Alt+<arrow>` window binds and drives the WM with **vim keys** instead:

| Keys | Action |
| --- | --- |
| `Alt+H/J/K/L` | focus window left/down/up/right |
| `Alt+Shift+H/J/K/L` | move window left/down/up/right |
| `Alt+1..9` | focus workspace *n* |
| `Alt+Shift+1..9` | send window to workspace *n* and follow |
| `Alt+A` / `Alt+S` / `Alt+D` | prev / next / most-recent workspace |
| `Alt+Enter` | launch Windows Terminal (`wt`) |
| `Alt+T` / `Alt+Shift+Space` / `Alt+F` | toggle tiling / floating / fullscreen |
| `Alt+M` | minimize the focused window |
| `Alt+V` | toggle split direction |
| `Alt+R` | enter resize mode (then H/J/K/L or arrows; `Esc` exits) |
| `Alt+Shift+P` | pause mode (suspend binds; `Alt+Shift+P` again to resume) |
| `Alt+Shift+Q` | close window |
| `Alt+Shift+R` / `Alt+Shift+W` / `Alt+Shift+E` | reload config / redraw / exit WM |

## Bar widget (Zebar)

The bar is kept at **design parity with the macOS host's sketchybar** bar
(`dotfiles-MacBook/sketchybar`): same module order, floating rounded geometry,
CaskaydiaCove Nerd Font, Tokyo Night Storm palette, semantic load colors
(cpu/mem/disk green→yellow→red, volume cyan) and glyphs. The shared contract lives
in **`PARITY.md`** (an identical copy sits in `dotfiles-MacBook/sketchybar/`) —
change both bars together. Layout:

```
logo · workspaces · [binding-mode] · front-app · pomodoro | clock | media · network · volume · disk · memory · cpu · battery · weather · power
```

`binding-mode` is Windows-only (GlazeWM binding modes; macOS has no twin); macOS's
`caffeinate` keep-awake toggle is likewise macOS-only.

Three widgets are interactive, ported from
[`Gerrrt/yasb-glazewm-config`](https://github.com/Gerrrt/yasb-glazewm-config):

| Widget | What | Interaction |
| --- | --- | --- |
| **Pomodoro** (left) | 25/5 work-break timer | click the time to start/pause, right-click to reset |
| **Media** (right) | now-playing title/artist | prev / play-pause / next (Zebar `media` provider) |
| **Power menu** (far right) | lock / sleep / restart / shut down | click the power icon to expand, click an action to run |

The power menu runs its actions with Zebar's `shellExec` (`shutdown` and
`rundll32`), so those two programs are whitelisted under
`privileges.shellCommands` in `zpack.json` — Zebar refuses any shell command a
widget hasn't declared. The `zebar` client is pinned to the `@3` major to match
the pinned Zebar app, so the `media` provider and `shellExec` are present.

## Editing

`glazewm/config.yaml` is the source of truth — edit it here, and (once symlinked)
`Alt+Shift+R` reloads it live. The Zebar widget is buildless React
(`vanilla-clear.html`); every file it needs lives under the symlinked directory
(a bundled `normalize.css`, no zebar-root dependency), so it drops in cleanly and
Zebar hot-reloads on edit. Like any buildless Zebar widget it still pulls React,
the Zebar client, and the Nerd Font icon CSS from CDNs at runtime, so first paint
needs a network round-trip — it is self-contained on disk, not offline-only.
