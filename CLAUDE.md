# CLAUDE.md — dotfiles-Windows

Project memory for Claude Code, auto-loaded every session. The Core rules live in
[dotfiles-core](https://github.com/Gerrrt/dotfiles-core); this repo does **not** vendor `core/`.

## What this repo is

`dotfiles-Windows` is the **native-host layer** of a ten-repo, three-layer dotfiles
fleet (Core → OS-native → Role → Showcase). It owns the Windows host: PowerShell as
the daily-driver shell, Windows Terminal, the scoop/winget package layer, `psmux`
(native tmux), and the bridge to Linux distros under WSL2.

## The rule that bites

It deliberately does **not** configure WSL distros — Core, Debian, and Kali
configure themselves from their own repos *inside* WSL. This repo's job is to make
the host excellent and then get out of the way. There is no vendored `core/`; the
shared zsh/tmux/nvim Core lives in the Linux repos, so don't reach for it here.

The nvim config here is kept in step via `nvim-sync.ps1` (it mirrors Core's nvim
tree for native-Windows Neovim) — sync it rather than hand-editing drift.

## Where things are

- `powershell/` — pwsh profile + modules
- `windows-terminal/` — Terminal settings
- `packages/` — scoop/winget manifests
- `psmux/` — native tmux-alike
- `install.ps1`, `bootstrap.ps1`, `uninstall.ps1` — entry points
- `wsl/` — the WSL bridge
