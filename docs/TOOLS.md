# TOOLS.md — host toolchain

The guiding rule for this repo: **the Windows host owns the daily-driver shell
and the terminal experience.** Offensive tooling is not installed or configured
here — it lives on the **Kali station** (its own repo, inside WSL). See that
repo for the offensive catalog.

## Terminal / productivity (native host, via scoop)

| Tool | Replaces | scoop name | Notes |
|------|----------|-----------|-------|
| starship | prompt | `starship` | Same `starship.toml` as the fleet (now tokyonight-storm) |
| zoxide | `cd` | `zoxide` | `cd` is rebound to `z` in core |
| fzf | — | `fzf` | + PSFzf module for Ctrl+t / Ctrl+r |
| ripgrep | grep | `ripgrep` | `grep` shadowed by `rg --smart-case` |
| fd | find | `fd` | named `fd` on Windows (no rename) |
| bat | cat | `bat` | `cat` shadowed; `catp` for paged |
| eza / lsd | ls | `eza` / `lsd` | eza preferred; lsd is the fallback |
| delta | diff pager | `delta` | wired into `.gitconfig` (full decorations) |
| bottom / btop-lhm | top | `bottom` / `btop-lhm` | `btop-lhm` reads hardware sensors |
| lazygit | — | `lazygit` | `lg` |
| yazi | file mgr | `yazi` | TUI file manager |
| atuin | history | `atuin` | optional shell history sync |
| neovim | editor | `neovim` | config vendored from Core (see nvim/) |
| jq / yq | — | `jq` / `yq` | JSON/YAML wrangling |
| hyperfine | `time` | `hyperfine` | benchmarking |
| tlrc | man | `tlrc` | `tldr` client (Rust) |

### 2026 additions (fleet parity with Core's `tools.zsh`)

| Tool | Replaces | scoop name | Alias | Notes |
|------|----------|-----------|-------|-------|
| xh | curl/HTTPie | `xh` | `http` / `https` | Rust HTTPie — poke APIs / web targets |
| glow | — | `glow` | `md` | render markdown in the terminal (engagement notes/READMEs) |
| doggo | dig | `doggo` | `dns` | modern dig (DNS recon) |
| sd | sed | `sd` | — | intuitive find/replace; own verb (never shadows sed) |
| gron | — | `gron` | — | greppable JSON |
| gum | — | `gum` | — | shell-script UI widgets (Charm) |

Aliases are **guarded** (`if (Test-Cmd ...)`) the same way the zsh aliases are —
on a box where a tool isn't installed, the classic command is untouched.

## Secrets — 1Password CLI (`op`)

`op` is cross-platform, so Core's `op.zsh` helpers are ported to PowerShell in
`powershell/core/40-op.ps1`. Installed via winget (`AgileBits.1Password.CLI`).

| Function | Does |
|----------|------|
| `opsecret <vault>/<item>/<field>` | `op read op://...` — fetch one secret |
| `openv <env-file> <command...>` | run a command with secrets injected from a `.env.op` template |
| `optoken <vault>/<item>` | copy a TOTP code to the clipboard |
| `opssh` | list SSH keys stored in 1Password |

The history handler in `10-tools.ps1` keeps `op read` / `op item` lines (and
anything matching password/secret/token) out of the saved PSReadLine history —
the PowerShell analog of Core's `HISTORY_IGNORE`.

## Host utilities worth having

- **Sysinternals** (`scoop install sysinternals`) — Procmon, Process Explorer,
  Autoruns. The best way to understand what Windows is actually doing; useful
  for general troubleshooting and for learning Windows internals.
- **Wireshark** (winget) — packet capture on host interfaces.
- **win32yank** — clipboard provider so Neovim's `unnamedplus` works on the host.

## Updates & maintenance

The fleet's "check + nudge, apply on demand" pattern (Core's `update.zsh` /
`maint.zsh`) is ported to the host:

| Command | Does |
|---------|------|
| *(startup nudge)* | once/day, backgrounded, prints `N updates available` if scoop/winget have upgrades |
| `up` | apply updates: `scoop update *` + cleanup, then `winget upgrade --all`. `up -y` auto-confirms winget |
| `update-check` | force the check now and refresh the nudge |
| `update-host` | legacy one-shot scoop+winget update (kept; `up` is the fleet-standard verb) |
| `maint-install [HH:MM]` | register the daily maintenance **Scheduled Task** (default 13:00) |
| `maint-run` / `maint-log [N\|-f]` / `maint-status` / `maint-uninstall` | run now / tail log / next-run info / remove |

The scheduled runner (`maint/Maintenance.ps1`) updates the **user-space** stack
automatically (scoop, mise, nvim plugins/parsers, PowerShell modules). `winget
upgrade --all` is **opt-in** (`MAINT_WINGET_UPGRADE=1`) because it can launch MSI
installers that prompt or restart apps — the Windows analog of why Core's maint
won't auto-upgrade system packages on Arch/Gentoo/Kali. `StartWhenAvailable` on
the task is the equivalent of systemd's `Persistent=true` (catch up if the box
was off).

## Virtualization (manual install)

VMware Workstation is **not** in the winget manifest on purpose: since the
Broadcom acquisition, Workstation Player is discontinued and Workstation Pro
(free for personal use) is gated behind a Broadcom account login, so winget and
choco can no longer fetch it — grab it from the Broadcom support portal by hand.
If you want a CLI-installable hypervisor instead, `Oracle.VirtualBox` works
through winget. (Day-to-day Linux still lives in WSL2 via the bridge, so a full
VM is only needed for non-WSL guests or snapshot-heavy lab work.)

## The host ↔ WSL seam

WSL2 with `networkingMode=mirrored` (see `wsl/windows.wslconfig.example`) lets
the host and your distros share network interfaces, so a service bound inside
WSL is reachable at the host's LAN IP without NAT gymnastics. The bridge
functions (`kali`, `cdwsl`, `hostip`, `wsl-restart`) live in
`powershell/os/31-wsl-bridge.ps1`.

That's the whole point of the split: the host gives you a great terminal and a
clean way into WSL; the **Kali station** owns everything offensive.

