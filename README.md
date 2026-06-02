# dotfiles-Windows

The **native-host layer** of my multi-OS dotfiles fleet. This repo owns the
Windows host: PowerShell as the daily-driver shell, Windows Terminal, the
scoop/winget package layer, and the bridge to my Linux distros running under
WSL2.

It deliberately does **not** configure WSL distros. Core, Debian, and Kali
configure themselves from their own repos *inside* WSL. This repo's job is to
make the host excellent and then get out of the way.

```
                ┌─────────────────────────────────────────┐
   this repo →  │  Windows host: pwsh + Terminal + scoop    │
                │  + WSL bridge (.wslconfig, mirrored net)  │
                └───────────────────┬───────────────────────┘
                                    │  wsl
                ┌───────────────────▼───────────────────────┐
   other repos →│  WSL2: Core / Debian / Kali (zsh/tmux/...)  │
                └─────────────────────────────────────────────┘
```

## Layer model (mirrors the zsh loader on the Linux/Mac repos)

`powershell/profile.ps1` is symlinked to `$PROFILE` and dot-sources fragments
in order:

1. **core/** — cross-fleet aliases, prompt (starship), history (PSReadLine),
   fuzzy nav (fzf/zoxide), update nudge, 1Password helpers, general helpers.
   Same feel as zsh everywhere.
2. **os/** — Windows-native: scoop/winget helpers, clipboard, the WSL bridge,
   scheduled maintenance.
3. **local.ps1** — machine-specific, gitignored. Secrets and per-host overrides.

There is intentionally **no offensive layer** here. The offensive role is unique
to the Kali station, same as everywhere else in the fleet — this repo is a
productivity/host repo only.

New fragments load automatically — the loader globs each layer directory in
name order, so dropping a `core/NN-name.ps1` or `os/NN-name.ps1` in is all it
takes (no `install.ps1` change needed).

## Install

Requires **PowerShell 7** (`pwsh`) and **Developer Mode** enabled (or run
elevated) so symlinks work.

```powershell
git clone <your-remote>/dotfiles-Windows.git
cd dotfiles-Windows
.\install.ps1                # packages + symlinks
# or, to only re-wire links:
.\install.ps1 -SkipPackages
```

Then:
1. Open a **new** PowerShell window to load the profile.
2. Set your name/email in `~/.gitconfig.local`.
3. Review `~/.wslconfig` and run `wsl --shutdown` to apply mirrored networking.
4. (Optional) `maint-install` to register the daily maintenance task.

## First-run troubleshooting

- **"cannot be loaded ... not digitally signed"** — execution policy. `install.ps1`
  now sets `RemoteSigned` for your user and unblocks the repo files automatically,
  but if you hit this *before* the script can even start, do it once by hand:
  `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`, then
  `Get-ChildItem -Recurse -File | Unblock-File`. If `Get-ExecutionPolicy -List`
  shows `MachinePolicy`/`UserPolicy` set, that's Group Policy (managed/gov
  machines) and you can't override it yourself.
- **Prefer `git clone` over downloading an archive.** Cloned files don't carry
  the "Mark of the Web," so the unblock step never comes up.
- **Use PowerShell 7 (`pwsh`), not Windows PowerShell 5.1.** The bootstrap
  tolerates 5.1 and warns you, but the profile targets the pwsh path — do daily
  work in pwsh.
- **A package fails to install?** The installer logs it and keeps going, then
  prints a `skipped:` summary. Re-run `.\install.ps1` to retry (installed apps
  are skipped). Some scoop packages with `persist` blocks (e.g. `btop-lhm`) can
  trip on a leftover config from an interrupted run — `scoop uninstall <name>`
  then reinstall, or drop it from `packages\scoopfile.json`.

## Layout

```
dotfiles-Windows/
├── install.ps1                  bootstrap (env var, packages, symlinks)
├── powershell/
│   ├── profile.ps1              loader (core→os→local)
│   ├── core/                    aliases, tools init, functions, update, op
│   │     00-aliases  10-tools  15-update  20-functions  40-op
│   ├── os/                      windows helpers + wsl bridge + maintenance
│   │     30-windows  31-wsl-bridge  40-maint
│   └── local.ps1.example        copy to local.ps1 (gitignored)
├── maint/Maintenance.ps1        unattended daily maint runner (Task Scheduler)
├── windows-terminal/settings.json
├── starship/starship.toml       same prompt as the fleet (tokyonight-storm)
├── git/ (.gitconfig, .gitignore_global)
├── ssh/config                   hardened (no ControlMaster on Win OpenSSH)
├── nvim/                        symlinked to %LOCALAPPDATA%\nvim (vendor Core)
├── wsl/windows.wslconfig.example  canonical host WSL2 config (mirrored net)
├── packages/ (scoopfile.json, winget.json, Install-Packages.ps1)
└── docs/ (TOOLS.md, PORTING-NOTES.md)
```

## Daily-driver cheatsheet

| Command | Does |
|---------|------|
| `ll` / `la` / `lt` | eza listings (long / all / tree) |
| `cat` / `catp` | bat (no-pager / paged) |
| `z foo` | zoxide jump; `cd` is rebound to `z` |
| `Ctrl+t` / `Ctrl+r` | fzf file picker / history search |
| `http` / `dns` / `md` | xh / doggo / glow (guarded if installed) |
| `lg` | lazygit |
| `serve [port]` | HTTP server in the CWD, prints the host LAN URL |
| `fif <term>` / `fbr` | find-in-files / fuzzy git-branch checkout |
| `up` / `up -y` | apply scoop+winget updates (`-y` auto-confirms winget) |
| `update-check` | force the "updates available" check now |
| `maint-install [HH:MM]` | register the daily maintenance task |
| `maint-run` / `maint-log -f` / `maint-status` | run now / follow log / next-run |
| `opsecret` / `optoken` / `openv` / `opssh` | 1Password CLI helpers |
| `kali` / `cdwsl` | jump into Kali / into Kali at the current dir |
| `wsls` / `hostip` | WSL distro status / host LAN IP |
| `tools` | open the host tool docs |

## Scope note

This repo is the **host/productivity layer only** — no offensive tooling is
installed or configured here. That role lives on the **Kali station** (its own
repo, inside WSL). The bridge functions (`kali`, `cdwsl`) are just how you get
there from the host shell.

