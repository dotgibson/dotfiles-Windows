# PORTING-NOTES.md — how Windows fits the matrix

The fleet's `PORTING-MATRIX.md` has a column per OS. Windows is the odd one out
because it isn't a zsh/Unix target — it's a PowerShell host that also runs your
Linux distros under WSL2. Here's the row, translated.

| Matrix concept (Linux/Mac)                 | Windows equivalent                                                                                                       |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| Package manager block (`apt`/`dnf`/`brew`) | `scoop` (CLI) + `winget` (GUI) — `packages/`                                                                             |
| Shell layer (`zsh`)                        | PowerShell 7 (`pwsh`) — `powershell/`                                                                                    |
| Shell loader (sources core→os→local)       | `powershell/profile.ps1` (core→os→local)                                                                                 |
| Clipboard (`pbcopy` / `clip` / `xclip`)    | `Set-Clipboard` / `Get-Clipboard` (aliased `pbcopy`/`pbpaste`)                                                           |
| Prompt (`starship`)                        | `starship` — same `starship.toml`, cross-shell                                                                           |
| Multiplexer (`tmux`)                       | **host:** psmux (native Windows tmux, reads `~/.tmux.conf`) + Windows Terminal panes · **WSL:** the real tmux, from Core |
| Runtime manager (`mise`)                   | mise has Windows support but is secondary; scoop owns most CLI runtimes                                                  |
| Editor (`nvim`)                            | nvim reads `%LOCALAPPDATA%\nvim`; vendor Core's config (see `nvim/`)                                                     |
| SSH config                                 | same hardened defaults **minus ControlMaster** (unsupported on Win OpenSSH)                                              |
| `update.zsh` (`up` + nudge)                | `powershell/core/15-update.ps1` (scoop/winget, no elevation)                                                             |
| `maint.zsh` + `dotfiles-maint.sh`          | `powershell/os/40-maint.ps1` + `maint/Maintenance.ps1` (Task Scheduler)                                                  |
| `op.zsh` (1Password helpers)               | `powershell/core/40-op.ps1` (`op` CLI is cross-platform)                                                                 |
| `history.zsh` (`HISTORY_IGNORE`)           | PSReadLine `AddToHistoryHandler` in `10-tools.ps1`                                                                       |
| MAC helpers (SELinux/AppArmor)             | n/a                                                                                                                      |
| Offensive layer (Kali only)                | n/a here — offensive role stays on the Kali station                                                                      |

## Newly ported from Core (2026 sync)

- **`up` + update nudge** — `core/15-update.ps1`. Once/day, backgrounded
  (`Start-Job`), no elevation (scoop/winget are user-space). `up` is the
  fleet-standard verb; the older `update-host` stays as a convenience.
- **Scheduled maintenance** — `os/40-maint.ps1` drives a Task Scheduler job
  running `maint/Maintenance.ps1`. `StartWhenAvailable` ≈ systemd `Persistent`.
  scoop/mise/nvim/PS-modules auto-update; **winget is opt-in**
  (`MAINT_WINGET_UPGRADE=1`) since it can run MSI installers — the same caution
  Core applies to system packages on Arch/Gentoo/Kali.
- **1Password helpers** — `core/40-op.ps1`, 1:1 with `op.zsh`.
- **History secret-filtering** — PSReadLine `AddToHistoryHandler` keeps
  password/secret/token/`op …` lines out of the saved history file.
- **2026 CLI tools + aliases** — xh (`http`), glow (`md`), doggo (`dns`), plus
  sd/gron/gum as their own verbs. scoopfile + guarded aliases.
- **starship palette** — realigned to **tokyonight-storm**, then revised so the
  bright accents are segment _text_ over two dark surface fills instead of
  glaring background bands (was a near-white-on-bright eye-strain prompt).
- **psmux (native host tmux)** — NEW. tmux now has no-WSL home on the host:
  scoop install (`psmux` bucket), config at `psmux/.tmux.conf` symlinked to
  `~/.tmux.conf`, `mux` helper in `os/32-psmux.ps1`. See "Multiplexer" below.
- **git config** — picked up Core's 2026 additions (fsmonitor, untrackedCache,
  rerere, rebase.updateRefs/autosquash, maintenance, fuller delta, expanded
  aliases) while keeping the Windows bits (autocrlf=true, longpaths, GCM,
  Windows excludesfile path).

> The new `core/` and `os/` fragments load automatically — `profile.ps1` globs
> each layer directory in name order, so no `install.ps1` change is needed for
> them. (`install.ps1` _was_ touched once, to symlink `psmux/.tmux.conf` →
> `~/.tmux.conf`, since psmux reads a real config file rather than being sourced.)
> The maintenance runner is invoked by path, so it doesn't need a symlink either.

## Multiplexer: the host story changed

Previously this repo punted host-side multiplexing entirely to Windows Terminal
panes and kept tmux strictly inside WSL. As of 2026 there's a native option:
**psmux** is a Rust/ConPTY Windows multiplexer that speaks tmux's command
language and reads `~/.tmux.conf`. So the host now has three layers of choice:

1. **Windows Terminal panes** — zero install, GUI-native, still fine for quick
   splits (keybinds in `windows-terminal/settings.json`).
2. **psmux** — real tmux semantics (sessions/windows/panes, persistence, copy
   mode, scripting) in pwsh, no WSL. This is the new default for serious
   host-side multiplexing.
3. **tmux in WSL** — unchanged; the genuine article for Linux-side work, owned
   by Core/Kali.

The vendored `psmux/.tmux.conf` sticks to portable tmux options so it can later
be unified with Core's tmux config (same filename, same language). What does NOT
carry to the host: the `vim-tmux-navigator` smart-pane script (Unix-shell
`is_vim` detection) and any `clip`/xclip copy commands — host clipboard goes
through `set-clipboard on` (OSC52) instead.

## Things that DON'T port (by design)

- **Offensive layer** — unique to the Kali station, same as everywhere else in
  the fleet. The Windows host is a productivity/host repo only.
- **sesh** — the tmux session-manager wrapper stays in Core for use inside WSL;
  on the host, `mux` (attach-or-create) covers the common case.
- **Full nvim tree** — belongs in Core and is vendored, not duplicated.
- **starship/zoxide init caching** — Core caches `init zsh` output to skip a
  subprocess per shell. Not ported: PowerShell's module/profile load dominates
  startup here and the caching machinery isn't worth the complexity. Revisit if
  `pwsh` cold-start ever feels slow (measure first).
- **MAC/SELinux/AppArmor** — no equivalent.
- **`getent`/`/etc/passwd` shell detection** — n/a on the host.

## Remaining manual steps

- **Re-vendor `nvim/` from Core.** The committed `nvim/` here is a thin shell;
  the real tree (lua/gerrrt/{config,plugins,servers,utils}) is authored in Core
  and vendored. Pull the current Core nvim tree in (subtree pull or a straight
  copy of `core/nvim/` → this repo's `nvim/`). `.luacheckrc` has been synced to
  Core's current version; the rest of the tree should follow the same way the
  Linux repos vendor it.
- **Align `psmux/.tmux.conf` with Core's tmux config.** The host config is a
  standalone, portable starter. When convenient, reconcile the prefix and
  keybinds with Core (the file leaves the prefix at tmux's default `C-b` and
  marks the remap to mirror) and decide whether to vendor Core's `.tmux.conf`
  here outright — psmux reads the same filename, so it's a clean subtree/copy
  the same way nvim is handled.

## Windows-only additions

- `wsl/windows.wslconfig.example` — canonical home for the host WSL2 config
  (mirrored networking) that the Kali repo references.
- `powershell/os/31-wsl-bridge.ps1` — the host↔WSL seam (`kali`, `cdwsl`,
  `hostip`, `wsl-restart`).
- `powershell/os/32-psmux.ps1` + `psmux/.tmux.conf` — native host multiplexer.
- `powershell/os/40-maint.ps1` + `maint/Maintenance.ps1` — Task Scheduler maint.
- Windows Terminal `settings.json`.

## Maintenance

- When **Core's** `starship.toml`, git config, or `.tmux.conf` changes, mirror
  the relevant bits here (or vendor them as a subtree the way the Linux repos do).
- Record the scoop/winget package names in the matrix's Windows column so
  future-you doesn't re-derive them (psmux lives in its own scoop bucket:
  `https://github.com/psmux/scoop-psmux`).
