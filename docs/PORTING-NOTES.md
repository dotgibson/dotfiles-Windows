# PORTING-NOTES.md — how Windows fits the matrix

The fleet's `PORTING-MATRIX.md` has a column per OS. Windows is the odd one out
because it isn't a zsh/Unix target — it's a PowerShell host that also runs your
Linux distros under WSL2. Here's the row, translated.

| Matrix concept (Linux/Mac) | Windows equivalent |
|----------------------------|--------------------|
| Package manager block (`apt`/`dnf`/`brew`) | `scoop` (CLI) + `winget` (GUI) — `packages/` |
| Shell layer (`zsh`) | PowerShell 7 (`pwsh`) — `powershell/` |
| Shell loader (sources core→os→local) | `powershell/profile.ps1` (core→os→local) |
| Clipboard (`pbcopy` / `clip` / `xclip`) | `Set-Clipboard` / `Get-Clipboard` (aliased `pbcopy`/`pbpaste`) |
| Prompt (`starship`) | `starship` — same `starship.toml`, cross-shell |
| Multiplexer (`tmux`) | Windows Terminal panes natively; tmux lives in WSL |
| Runtime manager (`mise`) | mise has Windows support but is secondary; scoop owns most CLI runtimes |
| Editor (`nvim`) | nvim reads `%LOCALAPPDATA%\nvim`; vendor Core's config (see `nvim/`) |
| SSH config | same hardened defaults **minus ControlMaster** (unsupported on Win OpenSSH) |
| `update.zsh` (`up` + nudge) | `powershell/core/15-update.ps1` (scoop/winget, no elevation) |
| `maint.zsh` + `dotfiles-maint.sh` | `powershell/os/40-maint.ps1` + `maint/Maintenance.ps1` (Task Scheduler) |
| `op.zsh` (1Password helpers) | `powershell/core/40-op.ps1` (`op` CLI is cross-platform) |
| `history.zsh` (`HISTORY_IGNORE`) | PSReadLine `AddToHistoryHandler` in `10-tools.ps1` |
| MAC helpers (SELinux/AppArmor) | n/a |
| Offensive layer (Kali only) | n/a here — offensive role stays on the Kali station |

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
- **starship palette** — realigned gruvbox → **tokyonight-storm** to match the
  rest of the fleet, the nvim theme, and the Windows Terminal scheme.
- **git config** — picked up Core's 2026 additions (fsmonitor, untrackedCache,
  rerere, rebase.updateRefs/autosquash, maintenance, fuller delta, expanded
  aliases) while keeping the Windows bits (autocrlf=true, longpaths, GCM,
  Windows excludesfile path).

> The new `core/` and `os/` fragments load automatically — `profile.ps1` globs
> each layer directory in name order, so no `install.ps1` change is needed. The
> maintenance runner is invoked by path, so it doesn't need a symlink either.

## Things that DON'T port (by design)

- **Offensive layer** — unique to the Kali station, same as everywhere else in
  the fleet. The Windows host is a productivity/host repo only.
- **tmux config / sesh** — Windows Terminal handles host-side multiplexing; the
  tmux + sesh configs stay in Core for use inside WSL.
- **Full nvim tree** — belongs in Core and is vendored, not duplicated.
- **starship/zoxide init caching** — Core caches `init zsh` output to skip a
  subprocess per shell. Not ported: PowerShell's module/profile load dominates
  startup here and the caching machinery isn't worth the complexity. Revisit if
  `pwsh` cold-start ever feels slow (measure first).
- **MAC/SELinux/AppArmor** — no equivalent.
- **`getent`/`/etc/passwd` shell detection** — n/a on the host.

## Remaining manual step

- **Re-vendor `nvim/` from Core.** The committed `nvim/` here is a thin shell;
  the real tree (lua/gerrrt/{config,plugins,servers,utils}) is authored in Core
  and vendored. Pull the current Core nvim tree in (subtree pull or a straight
  copy of `core/nvim/` → this repo's `nvim/`). `.luacheckrc` has been synced to
  Core's current version as part of this update; the rest of the tree should
  follow the same way the Linux repos vendor it.

## Windows-only additions

- `wsl/windows.wslconfig.example` — canonical home for the host WSL2 config
  (mirrored networking) that the Kali repo references.
- `powershell/os/31-wsl-bridge.ps1` — the host↔WSL seam (`kali`, `cdwsl`,
  `hostip`, `wsl-restart`).
- `powershell/os/40-maint.ps1` + `maint/Maintenance.ps1` — Task Scheduler maint.
- Windows Terminal `settings.json`.

## Maintenance

- When **Core's** `starship.toml` or git config changes, mirror the relevant
  bits here (or vendor them as a subtree the way the Linux repos do).
- Record the scoop/winget package names in the matrix's Windows column so
  future-you doesn't re-derive them.

