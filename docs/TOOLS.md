# TOOLS.md — host toolchain

The guiding rule for this repo: **the Windows host owns the daily-driver shell
and the terminal experience.** Offensive tooling is not installed or configured
here — it lives on the **Kali station** (its own repo, inside WSL). See that
repo for the offensive catalog.

## Terminal / productivity (native host, via scoop)

| Tool              | Replaces   | scoop name            | Notes                                                    |
| ----------------- | ---------- | --------------------- | -------------------------------------------------------- |
| starship          | prompt     | `starship`            | Same `starship.toml` as the fleet (now tokyonight-storm) |
| zoxide            | `cd`       | `zoxide`              | `cd` is rebound to `z` in core                           |
| fzf               | —          | `fzf`                 | + PSFzf module for Ctrl+t / Ctrl+r                       |
| ripgrep           | grep       | `ripgrep`             | `grep` shadowed by `rg --smart-case`                     |
| fd                | find       | `fd`                  | named `fd` on Windows (no rename)                        |
| bat               | cat        | `bat`                 | `cat` shadowed; `catp` for paged                         |
| eza / lsd         | ls         | `eza` / `lsd`         | eza preferred; lsd is the fallback                       |
| delta             | diff pager | `delta`               | wired into `.gitconfig` (full decorations)               |
| bottom / btop-lhm | top        | `bottom` / `btop-lhm` | `btop-lhm` reads hardware sensors                        |
| lazygit           | —          | `lazygit`             | `lg`                                                     |
| yazi              | file mgr   | `yazi`                | TUI file manager                                         |
| atuin             | history    | `atuin`               | optional shell history sync                              |
| neovim            | editor     | `neovim`              | config vendored from Core (see nvim/)                    |
| jq / yq           | —          | `jq` / `yq`           | JSON/YAML wrangling                                      |
| hyperfine         | `time`     | `hyperfine`           | benchmarking                                             |
| tlrc              | man        | `tlrc`                | `tldr` client (Rust)                                     |

### 2026 additions (fleet parity with Core's `tools.zsh`)

| Tool  | Replaces    | scoop name            | Alias                                         | Notes                                                                                                                                                                                |
| ----- | ----------- | --------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| xh    | curl/HTTPie | `xh`                  | `http` / `https`                              | Rust HTTPie — poke APIs / web targets                                                                                                                                                |
| glow  | —           | `glow`                | `gmd`                                         | render markdown in the terminal (engagement notes/READMEs); `gmd` (not `md`, which is the built-in mkdir)                                                                            |
| doggo | dig         | `doggo`               | `dns`                                         | modern dig (DNS recon)                                                                                                                                                               |
| sd    | sed         | `sd`                  | —                                             | intuitive find/replace; own verb (never shadows sed)                                                                                                                                 |
| gron  | —           | `gron`                | —                                             | greppable JSON                                                                                                                                                                       |
| gum   | —           | `gum`                 | —                                             | shell-script UI widgets (Charm)                                                                                                                                                      |
| tv    | —           | `television` (extras) | `tvim` `ttext` `tcd` `trepo` `tbranch` `tenv` | television fuzzy finder; wrappers in `core/25-television.ps1`. NOT given Ctrl+R (atuin owns it) — named verbs only. Channel availability (`dirs` etc.) depends on tv's cable config. |

Aliases are **guarded** (`if (Test-Cmd ...)`) the same way the zsh aliases are —
on a box where a tool isn't installed, the classic command is untouched.

## Terminal multiplexer — psmux (native host)

The fleet runs tmux inside WSL, but the **host** now gets a real multiplexer too.
[psmux](https://github.com/psmux/psmux) is a native Windows terminal multiplexer
written in Rust: it drives Windows ConPTY directly, speaks the tmux command
language, and reads a `~/.config/psmux/psmux.conf` — so panes, windows, and session
persistence work in **pwsh on the host** without WSL, Cygwin, or MSYS2. It ships
`psmux`, `pmux`, and a `tmux` shim, so muscle memory carries straight over.

| Item     | Detail                                                                                                  |
| -------- | ------------------------------------------------------------------------------------------------------- |
| Install  | scoop (`psmux` bucket → `psmux` app), in `packages/scoopfile.json`                                      |
| Commands | `psmux` / `pmux` / `tmux` (identical)                                                                   |
| Config   | `psmux/psmux.conf` (+ `psmux.reset.conf`, `scripts/`), symlinked to `~/.config/psmux/` by `install.ps1` |
| Helper   | `mux [session]` (in `os/32-psmux.ps1`) — attach-or-create; defaults to `main`                           |
| Requires | Windows 10/11 + PowerShell 7 (already the host target)                                                  |

The vendored `psmux/psmux.conf` is deliberately limited to **portable** tmux
options (prefix remapped to `C-a`, mouse off, vi copy-mode,
`base-index 1`, OSC52 clipboard, tokyonight-storm status bar) so the same file
can later be shared with / vendored from Core the way the nvim tree is.

**Two caveats worth knowing:**

- psmux is **much newer** than the rest of the stack (first releases early 2026).
  It's solid and actively developed, but treat version bumps with the same
  caution you'd give any young tool — verify on update rather than blind-upgrade.
- **vim-tmux-navigator's** smart `<C-h/j/k/l>` pane-crossing is **not** wired in
  the host config: it relies on a Unix-shell `is_vim` detection script that
  doesn't apply to a native Windows multiplexer. Inside nvim those keys still
  move between nvim splits; crossing the boundary into a psmux pane uses psmux's
  own pane keys (prefix + arrows / your binds). It works as expected inside WSL,
  where the real navigator script runs.

## Secrets — 1Password CLI (`op`)

`op` is cross-platform, so Core's `op.zsh` helpers are ported to PowerShell in
`powershell/core/40-op.ps1`. Installed via winget (`AgileBits.1Password.CLI`).

| Function                          | Does                                                          |
| --------------------------------- | ------------------------------------------------------------- |
| `opsecret <vault>/<item>/<field>` | `op read op://...` — fetch one secret                         |
| `openv <env-file> <command...>`   | run a command with secrets injected from a `.env.op` template |
| `optoken <vault>/<item>`          | copy a TOTP code to the clipboard                             |
| `opssh`                           | list SSH keys stored in 1Password                             |

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

| Command                                                                | Does                                                                                                 |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| _(startup nudge)_                                                      | once/day, backgrounded, prints `N updates available` if scoop/winget have upgrades                   |
| `up`                                                                   | apply updates: `scoop update *` + cleanup, then `winget upgrade --all`. `up -y` auto-confirms winget |
| `update-check`                                                         | force the check now and refresh the nudge                                                            |
| `update-host`                                                          | legacy one-shot scoop+winget update (kept; `up` is the fleet-standard verb)                          |
| `maint-install [HH:MM]`                                                | register the daily maintenance **Scheduled Task** (default 13:00)                                    |
| `maint-run` / `maint-log [N\|-f]` / `maint-status` / `maint-uninstall` | run now / tail log / next-run info / remove                                                          |
| `shell-bench [runs]`                                                   | time a cold `pwsh` start (full profile), default 5 runs — measure before tuning startup              |
| `prof-trace`                                                           | load the full profile with tracing on and print a slowest-first per-fragment / per-tool breakdown    |
| `init-cache-clear`                                                     | drop the cached tool-init scripts (`%LOCALAPPDATA%\dotfiles\init-cache`); they regenerate next start |

Tool shell-integration scripts (`starship`/`zoxide`/`mise`/`atuin`/`carapace`)
are cached on first run and only regenerated when the tool's binary is newer
than the cache (e.g. after a scoop upgrade), trimming a subprocess spawn per tool
off every cold start. `init-cache-clear` forces a rebuild if you change a tool's
init flags in `core/10-tools.ps1`.

**Which profiler?** There are three, each for a different question:

| Use                         | When                                                                                                                                                                                               |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `shell-bench [runs]`        | "How long is a cold start?" — wall-clock totals only.                                                                                                                                              |
| `prof-trace`                | "Where does the time go?" — per-fragment / per-tool breakdown.                                                                                                                                     |
| `maint/Measure-Profile.ps1` | "Which fragment HANGS?" — writes a breadcrumb log before each fragment, so the last line names the one that froze. Reach for this only when a shell hangs on load and `prof-trace` prints nothing. |

**Startup speed.** Two items dominate a cold shell and are therefore **off by
default**: `Terminal-Icons` (~1.1s — only themes raw `Get-ChildItem`, which your
`ls`/`ll` bypass via `eza --icons`) and `carapace` (~1.5s completion generation —
pwsh native completion + CompletionPredictor + atuin cover most of it). Re-enable
either with a User-scope env var (`DOTFILES_TERMINAL_ICONS=1` / `DOTFILES_CARAPACE=1`;
see `powershell/local.ps1.example`). Measure with `shell-bench`, break it down with
`prof-trace`.

**Modules off OneDrive.** If `Documents` is redirected to OneDrive, the default
CurrentUser module path (`Documents\PowerShell\Modules`) is OneDrive-synced, and
importing modules from there can add **several seconds to every shell start**
(placeholder hydration / sync I/O). `profile.ps1` prepends a local dir
(`%LOCALAPPDATA%\PowerShell\Modules`) to `$env:PSModulePath`; the installer and
maintenance runner `Save-Module` managed modules there. To migrate an existing
machine, run `modules-localize` once (ideally from `pwsh -NoProfile` so no module
DLLs are locked), then open a new shell.

The scheduled runner (`maint/Maintenance.ps1`) updates the **user-space** stack
automatically (scoop, mise, nvim plugins/parsers, PowerShell modules). `winget
upgrade --all` is **opt-in** (`MAINT_WINGET_UPGRADE=1`) because it can launch MSI
installers that prompt or restart apps — the Windows analog of why Core's maint
won't auto-upgrade system packages on Arch/Gentoo/Kali. `StartWhenAvailable` on
the task is the equivalent of systemd's `Persistent=true` (catch up if the box
was off). Because psmux is installed through scoop, the maint job upgrades it
along with the rest of the scoop apps.

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

That's the whole point of the split: the host gives you a great terminal —
now with psmux for native multiplexing — and a clean way into WSL; the **Kali
station** owns everything offensive.
