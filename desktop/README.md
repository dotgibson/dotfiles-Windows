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
| `zebar/vanilla-clear/` | Zebar v3 widget pack (`zpack.json`) — clock, GlazeWM workspaces, net/cpu/mem/battery/weather | `~/.glzr/zebar/vanilla-clear` |

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
| GlazeWM | `glzr-io.GlazeWM` | tiling window manager |
| Zebar | `glzr-io.Zebar` | top status bar |
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

## Editing

`glazewm/config.yaml` is the source of truth — edit it here, and (once symlinked)
`Alt+Shift+R` reloads it live. The Zebar widget is buildless React
(`vanilla-clear.html`); every file it needs lives under the symlinked directory
(a bundled `normalize.css`, no zebar-root dependency), so it drops in cleanly and
Zebar hot-reloads on edit. Like any buildless Zebar widget it still pulls React,
the Zebar client, and the Nerd Font icon CSS from CDNs at runtime, so first paint
needs a network round-trip — it is self-contained on disk, not offline-only.
