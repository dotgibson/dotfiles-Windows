# Changelog

All notable changes to this repo. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this is a personal dotfiles repo,
so entries are grouped by theme rather than strict semver releases.

## [Unreleased] — DX/UX overhaul

A structural + terminal-UX pass focused on a world-class bootstrap and shell
experience, grouped by theme.

### CI / structure (backend)

- **Hermetic, incremental CI** — GitHub Actions pinned to commit SHAs; Pester and
  PSScriptAnalyzer pinned to exact versions; PSGallery modules cached; a
  `detect-changes` gate skips the Windows jobs for docs-only changes.
- **Coverage gate** — Pester enforces ≥85% coverage on the pure-helper library.
- **`uninstall.ps1`** — reverse the bootstrap; removes only symlinks that point
  back into the repo, with `-DryRun` / `-RestoreBackups`.
- **Pre-commit hook** — `.githooks/pre-commit` runs the dependency-free validator;
  `install.ps1` wires `core.hooksPath`.
- **Fragment-load health gate** — the profile records any fragment that fails to
  load; `dotfiles-doctor` reports it.
- **More host-layer tests** — extracted pure helpers (`ConvertTo-WslPath`,
  `Get-FragmentHealthResult`, the uninstall link map) with behavioral tests.
- **Pinned module floors** — `packages/modules.ps1` carries `-MinimumVersion`
  floors for a reproducible baseline without freezing maintenance updates.
- **Dependabot** for the pinned actions.
- **Install transcript log** under `%LOCALAPPDATA%\dotfiles\logs`.
- **editorconfig enforcement** (final newline / trailing whitespace / LF) in the
  validator and Pester suite.
- **Manifest provenance** — winget ids must be `Publisher.Package`; scoop apps
  must name a declared bucket.
- This changelog.

### Terminal UX

- **`install.ps1 -DryRun`** previews every change and mutates nothing; `-Help`
  prints usage; `-NonInteractive` / `-Yes` for unattended runs.
- **Graceful interrupts** — `install.ps1` and the package installer print where
  they stopped (and close the log) on Ctrl-C or error.
- **Unified error/warning layout** — `Write-DotErr` / `Write-DotWarn` used across
  the entry points.
- **`NO_COLOR` + `DOTFILES_ASCII`** fallbacks across every renderer.
- **Install progress** — per-package `[n/total]` with elapsed time.
- **Interactive overwrite** — confirm before backing up a real user file; stale
  links are rewired silently.
- **Tab-completion** for `dothelp` filters, derived from the catalog.
- **Zero-config onboarding** — prompt for git name/email at install time.
- **`dotfiles-doctor -Fix`** opt-in remediation for the common issues.
- **`dothelp -i`** fuzzy command picker (fzf) that copies the pick.
- **`serve -Local`** — opt-in localhost-only bind (`127.0.0.1`) for the quick
  CWD HTTP server; LAN exposure stays the default.

### Fixes

- **`md` no longer shadows `mkdir`** — the glow markdown-render alias was bound to
  `md`, clobbering PowerShell's built-in `md` (mkdir). It's now `gmd`; `md` is
  mkdir again. README, `docs/TOOLS.md`, and the `dothelp` catalog updated.
- **`tools` command implemented** — the cheatsheet advertised `tools` ("open the
  host tool docs") but nothing defined it. It now renders `docs/TOOLS.md` (glow →
  bat → nvim → plain), and is listed in `dothelp`.
- **Dead-shim guards for `fif` / `fbr`** — a tool that *resolves* on PATH but
  won't *launch* (a stale Chocolatey shim, or a scoop shim whose app was removed,
  shadowing the real binary) produced raw `Program rg.exe failed to run` /
  `cannot find file ...fzf.exe` errors. A new `Test-CmdRuns` helper probes
  executability so `fif`/`fbr` (and the same class of `Ctrl+t`/`Ctrl+r` breakage)
  fail with an actionable fix hint instead.
- **`dotfiles-doctor` now checks executability** — a new *Core toolchain runs*
  probe flags tools that resolve but won't launch, which the resolve-only check
  could not see.
- **`tools` / `gmd` no longer abort when `less` is absent** — glow (and bat) page
  through `$PAGER`, defaulting to `less`, which isn't on a stock Windows box, so
  `glow --pager` died with `exec: "less" not found`. Both now pass paging flags
  only when a pager actually exists and render inline otherwise.

_Per-finding backlog IDs and their status live in
[`docs/ARCHITECTURE-AUDIT.md`](docs/ARCHITECTURE-AUDIT.md) — the single ID
registry, so this log stays prose with no competing `B#`/`U#` scheme._
