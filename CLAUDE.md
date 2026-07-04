# CLAUDE.md — dotfiles-Windows

Project memory for Claude Code, auto-loaded every session. The shared Core rules
live in [dotfiles-core](https://github.com/dotgibson/dotfiles-core).

## What this repo is

`dotfiles-Windows` is the **native-host layer** of a **ten-repo dotfiles system**
built on a three-layer model (Core → OS-native → Role). It owns the Windows host:
PowerShell as the daily-driver shell, Windows Terminal, the scoop/winget package
layer, `psmux` (native tmux), and the bridge to Linux distros under WSL2.

## The rule that bites

It deliberately does **not** configure WSL distros — Core and Kali
configure themselves from their own repos *inside* WSL. This repo's job is to make
the host excellent and then get out of the way.

This repo does **not** vendor the `dotfiles-core` `git subtree` (the canonical
fleet is `scripts/os-repos.txt` in dotfiles-core, which deliberately excludes
Windows). Don't confuse that with this repo's own PowerShell **`powershell/core/`**
module — same word, different thing: `powershell/core/` is native pwsh config that
lives and is edited here. Two assets are mirrored *from* dotfiles-core: `nvim/` (via
`nvim-sync.ps1`) and `starship/starship.toml` (via `starship-sync.ps1`, since
starship.toml is cross-shell) — sync those rather than hand-editing drift.

## Where things are

- `powershell/` — pwsh profile + modules (incl. the `core/` pwsh layer)
- `windows-terminal/` — Terminal settings
- `packages/` — scoop/winget manifests
- `psmux/` — native tmux-alike
- `nvim/` — Neovim config mirrored from dotfiles-core via `nvim-sync.ps1`
- `starship/` — cross-shell prompt config mirrored from dotfiles-core via `starship-sync.ps1`
- `git/` — `.gitconfig` / `.gitignore_global`
- `maint/Maintenance.ps1` — the daily maintenance runner (control surface: `os/40-maint.ps1`)
- `ssh/config` — SSH client config
- `docs/` — `TOOLS.md`, `PORTING-NOTES.md`, `ARCHITECTURE-AUDIT.md`
- `tests/` — Pester test suite
- `install.ps1`, `bootstrap.ps1`, `uninstall.ps1` — entry points
- `wsl/` — the WSL bridge
