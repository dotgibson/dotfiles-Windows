# dotfiles-Windows

The **native-host layer** of my multi-OS dotfiles fleet. This repo owns the
Windows host: PowerShell as the daily-driver shell, Windows Terminal, the
scoop/winget package layer, and the bridge to my Linux distros running under
WSL2.

It deliberately does **not** configure WSL distros. Core, Debian, and Kali
configure themselves from their own repos _inside_ WSL. This repo's job is to
make the host excellent and then get out of the way.

```
                ┌─--────────────────────────────────────────┐
   this repo →  │  Windows host: pwsh + Terminal + scoop    │
                │  + psmux (native tmux) + WSL bridge       │
                └───────────────────┬───────────────────────┘
                                    │  wsl
                ┌───────────────────▼──────────────────────--─┐
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
   psmux multiplexer helper, scheduled maintenance.
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

### One-liner (bootstrap)

From a fresh box, `bootstrap.ps1` clones the repo and runs the installer for you
(it needs `git` and `pwsh` 7+):

```powershell
irm https://raw.githubusercontent.com/Gerrrt/dotfiles-Windows/main/bootstrap.ps1 | iex
```

Knobs (all optional env vars): `DOTFILES_DIR` (clone location), `DOTFILES_REF`
(pin a commit/tag for a reproducible setup), `DOTFILES_REPO` (your fork's URL),
`DOTFILES_BOOTSTRAP_ARGS` (extra `install.ps1` args, e.g. `'-SkipPackages'`).

**Integrity-gated** — verify the script against the pinned hash before running it
(piping straight to `iex` trusts whatever the URL serves):

```powershell
$b = irm https://raw.githubusercontent.com/Gerrrt/dotfiles-Windows/main/bootstrap.ps1
$h = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes(($b -replace "`r`n","`n")))).ToLower()
if ($h -eq '7082698b8cf7d7d6b4203d5bacc6335ce26c5b21a4949af01d95c52de4bdd772') { $b | iex }
else { Write-Error "bootstrap.ps1 hash mismatch: $h" }
```

bootstrap.ps1 never pipes a further network script into `iex` itself: it clones
over git (pin `DOTFILES_REF` for an exact, content-addressed checkout) and hands
off to `install.ps1`, where scoop's installer stays behind the existing
`DOTFILES_SCOOP_SHA256` gate. <!-- bootstrap.ps1 SHA-256 (LF-normalized): 7082698b8cf7d7d6b4203d5bacc6335ce26c5b21a4949af01d95c52de4bdd772 -->

### Manual

```powershell
git clone <your-remote>/dotfiles-Windows.git
cd dotfiles-Windows
.\install.ps1                # packages + symlinks
# or, to only re-wire links:
.\install.ps1 -SkipPackages
# preview every change without touching anything:
.\install.ps1 -DryRun
# unattended (CI / no prompts):
.\install.ps1 -NonInteractive
.\install.ps1 -Help          # full option list
```

The installer is idempotent (re-running only fixes what drifted), prompts before
backing up a real file it's about to replace, and on the first run asks for your
git name/email. To reverse it:

```powershell
.\uninstall.ps1              # remove only the symlinks that point into this repo
.\uninstall.ps1 -RestoreBackups   # also restore the newest *.bak per link
.\uninstall.ps1 -DryRun
```

Then:

1. Open a **new** PowerShell window to load the profile.
2. Set your name/email in `~/.gitconfig.local`.
3. Review `~/.wslconfig` and run `wsl --shutdown` to apply mirrored networking.
4. (Optional) `maint-install` to register the daily maintenance task.
5. (Optional) `mux` to drop into a persistent psmux session.

## First-run troubleshooting

- **"cannot be loaded ... not digitally signed"** — execution policy. `install.ps1`
  now sets `RemoteSigned` for your user and unblocks the repo files automatically,
  but if you hit this _before_ the script can even start, do it once by hand:
  `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`, then
  `Get-ChildItem -Recurse -File | Unblock-File`. If `Get-ExecutionPolicy -List`
  shows `MachinePolicy`/`UserPolicy` set, that's Group Policy (managed/gov
  machines) and you can't override it yourself.
- **Prefer `git clone` over downloading an archive.** Cloned files don't carry
  the "Mark of the Web," so the unblock step never comes up.
- **Pinning the bootstrap's third-party fetches (supply chain).** The scoop
  installer can be integrity-gated: set `DOTFILES_SCOOP_SHA256` to the expected
  hash and the installer aborts on mismatch. The psmux `ppm` plugin clone can be
  pinned to an exact commit/tag with `DOTFILES_PPM_REF`; otherwise it tracks the
  default branch, and the installer verifies the expected `ppm\` folder is present
  before copying it.
- **Use PowerShell 7 (`pwsh`), not Windows PowerShell 5.1.** The bootstrap
  tolerates 5.1 and warns you, but the profile targets the pwsh path — do daily
  work in pwsh.
- **A package fails to install?** The installer logs it and keeps going, then
  prints a `skipped:` summary. Re-run `.\install.ps1` to retry (installed apps
  are skipped). Some scoop packages with `persist` blocks (e.g. `btop-lhm`) can
  trip on a leftover config from an interrupted run — `scoop uninstall <name>`
  then reinstall, or drop it from `packages\scoopfile.json`.
- **Garbled glyphs or unwanted colour?** Output honours
  [`NO_COLOR`](https://no-color.org) (set it to strip all colour) and
  `DOTFILES_ASCII=1` (swap the `✓ ✗ → •` glyphs for ASCII on a legacy codepage
  console). Both also apply to `install.ps1`, `dotfiles-doctor`, and `dothelp`.
- **Something half-loaded?** Run `dotfiles-doctor` — the _Profile fragments_
  check reports any fragment that failed to load, and `dotfiles-doctor -Fix`
  auto-remediates the common issues (execution policy, missing links, modules on
  OneDrive).

## Layout

```
dotfiles-Windows/
├── install.ps1                  bootstrap (env var, packages, symlinks)
├── uninstall.ps1                remove repo symlinks (optionally restore backups)
├── .githooks/pre-commit         runs tests/Invoke-Validation.ps1 before commits
├── powershell/
│   ├── profile.ps1              loader (core→os→local)
│   ├── core/                    aliases, shared lib, tool inits, functions, completions, help
│   │     00-aliases  05-lib  10-tools  15-update  20-functions  25-television
│   │     40-op  45-crypto  50-completions  55-help  57-health-nudge
│   ├── os/                      windows helpers + wsl bridge + psmux + maint + doctor
│   │     30-windows  31-wsl-bridge  32-psmux  33-psmux-pill  40-maint  45-doctor
│   └── local.ps1.example        copy to local.ps1 (gitignored)
├── maint/Maintenance.ps1        unattended daily maint runner (Task Scheduler)
├── windows-terminal/settings.json
├── starship/starship.toml       same prompt as the fleet (tokyonight-storm)
├── git/ (.gitconfig, .gitignore_global)
├── ssh/config                   hardened (no ControlMaster on Win OpenSSH)
├── psmux/psmux.conf             native host tmux (psmux), symlinked to ~/.config/psmux/
│       psmux.reset.conf  scripts/   (keybinds split out + popup helper scripts)
├── nvim/                        symlinked to %LOCALAPPDATA%\nvim (vendor Core)
├── wsl/windows.wslconfig.example  canonical host WSL2 config (mirrored net)
├── packages/ (scoopfile.json, winget.json, Install-Packages.ps1)
└── docs/ (TOOLS.md, PORTING-NOTES.md)
```

## Daily-driver cheatsheet

| Command                                       | Does                                                                          |
| --------------------------------------------- | ----------------------------------------------------------------------------- |
| `ll` / `la` / `lt`                            | eza listings (long / all / tree)                                              |
| `cat` / `catp`                                | bat (no-pager / paged)                                                        |
| `z foo`                                       | zoxide jump; `cd` is rebound to `z`                                           |
| `Ctrl+t` / `Ctrl+r`                           | fzf file picker / history search                                              |
| `http` / `dns` / `gmd`                        | xh / doggo / glow (guarded if installed; `gmd` renders markdown)              |
| `lg`                                          | lazygit                                                                       |
| `serve [port] [-Local]`                       | HTTP server in the CWD; prints the host LAN URL (`-Local` binds localhost only) |
| `fif <term>` / `fbr`                          | find-in-files / fuzzy git-branch checkout                                     |
| `tmux` / `psmux` / `pmux`                     | native host multiplexer (psmux; reads `~/.config/psmux/psmux.conf`)           |
| `mux [session]`                               | attach-or-create a psmux session (defaults to `main`)                         |
| `psmux-pill-enable` / `psmux-pill-disable`    | enable/disable the file-backed operator/VPN status pill (off the render path) |
| `up` / `up -y` / `up -n`                      | apply scoop+winget updates (`-y` auto-confirms winget; `-n`/`-Preview` lists only) |
| `update-check`                                | force the "updates available" check now                                       |
| `maint-install [HH:MM]`                       | register the daily maintenance task                                           |
| `maint-run` / `maint-log -f` / `maint-status` | run now / follow log / next-run                                               |
| `opsecret` / `optoken` / `openv` / `opssh`    | 1Password CLI helpers                                                         |
| `kali` / `cdwsl`                              | jump into Kali / into Kali at the current dir                                 |
| `wsls` / `hostip`                             | WSL distro status / host LAN IP                                               |
| `tools`                                       | open the host tool docs                                                       |
| `dothelp [filter]` / `dothelp -i`             | in-shell command index (`-i` = fzf picker, copies the pick)                   |
| `dotfiles-doctor [-Fix]`                      | health-check the setup, and optionally auto-remediate                         |

## Scope note

This repo is the **host/productivity layer only** — no offensive tooling is
installed or configured here. That role lives on the **Kali station** (its own
repo, inside WSL). The bridge functions (`kali`, `cdwsl`) are just how you get
there from the host shell. psmux gives you tmux-style multiplexing _on the host_;
the genuine tmux for Linux work still lives in WSL.

## Development

```powershell
# one-time: provision the same test toolchain CI uses (Pester + PSScriptAnalyzer,
# pinned to the CI versions; idempotent). A test gates these against ci.yml drift.
pwsh -NoProfile -File tests/Install-DevDeps.ps1

# fast, dependency-free gate (syntax + JSON/manifests + module pins + editorconfig):
pwsh -NoProfile -File tests/Invoke-Validation.ps1
# ^ also runs PSScriptAnalyzer automatically IF it's installed (errors gate the
#   run); it's skipped cleanly when absent, so the gate stays Gallery-free offline.

# full behavioral suite (needs Pester 5):
Invoke-Pester -Path tests
```

`install.ps1` wires `core.hooksPath = .githooks`, so the validator runs on every
commit (bypass a single one with `git commit --no-verify`). CI mirrors this: a
fast Linux gate, then PSScriptAnalyzer + Pester (with a coverage gate) on Windows
— heavy jobs are skipped for docs-only changes. Actions are pinned to commit
SHAs and kept current by Dependabot. See [CHANGELOG.md](CHANGELOG.md) for the
DX/UX overhaul history.
