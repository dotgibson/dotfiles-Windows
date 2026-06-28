# Changelog

All notable changes to this repo. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this is a personal dotfiles repo,
so entries are grouped by theme rather than strict semver releases.

## [Unreleased] — DX/UX overhaul

A structural + terminal-UX pass focused on a world-class bootstrap and shell
experience, grouped by theme.

### Security / robustness (install)

- **`install.ps1` now uses `-LiteralPath` for every existence/copy/move/remove**
  in `Link-Item` and the seed/ppm steps. Bare `Test-Path`/`Copy-Item`/`Move-Item`
  treat `[`/`]` as wildcards, so a profile path containing brackets could read an
  existing real config as absent — skipping the back-up branch and clobbering it
  with no `.bak`. Brackets are now matched literally.
- **`DOTFILES_PPM_REF` is rejected when it begins with `-`** and the ppm
  `git checkout` gained a `--` terminator, closing the argument-injection seam
  (e.g. `--upload-pack=…`) that `bootstrap.ps1` already guards for `DOTFILES_REF`.
- **Dependency probes scoped to real executables** — `Get-Command gum/git/scoop/winget`
  now pass `-CommandType Application`, so a user-defined function/alias of the same
  name can no longer satisfy a presence check (the repo's profile encourages such
  wrappers, which previously could flip `Test-DotGum` true with no real `gum`).

### CI / structure (backend)

- **`nvim-sync` bot** (`.github/workflows/nvim-sync.yml`) — runs `nvim-sync.ps1`
  weekly (and on demand) and opens a PR when Core's `nvim/` tree has actually
  moved ahead, so the host editor config can't silently fall behind. Judges drift
  on the Lua tree only (ignores `.core-ref`'s per-run timestamp). First-party
  (`GITHUB_TOKEN` + `gh`), no third-party action.
- **`package-freshness` bot** (`.github/workflows/package-freshness.yml` +
  `packages/Check-PackageFreshness.ps1`) — weekly on `windows-latest`, resolves the
  live scoop/winget version of each managed app and files a deduplicated findings
  issue when any is ahead of `packages.lock.json`. Findings only: re-pinning still
  runs locally via `Update-PackageLock.ps1` (it needs the apps installed).
- **Hermetic, incremental CI** — GitHub Actions pinned to commit SHAs; Pester and
  PSScriptAnalyzer pinned to exact versions; PSGallery modules cached; a
  `detect-changes` gate skips the Windows jobs for docs-only changes.
- **PSScriptAnalyzer signature gate** — after the pinned install, CI asserts the
  module manifest is Authenticode `Valid` and Microsoft-signed before running the
  analyzer, failing the build otherwise. Closes the last supply-chain gap in the
  fleet-wide CI-tool-download hardening (the Windows analogue of the SHA-256
  verification the Linux gate tools get via dotfiles-core's `setup-core-tools`).
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

- **Retired the `debian` WSL-jump helper** — `dotfiles-Debian` is no longer part of
  the fleet and Debian isn't a target distro, so the `debian` shortcut is removed
  from `os/31-wsl-bridge.ps1` (function + `provides:` line), the `dothelp` WSL-bridge
  catalog (`Help.Helpers.ps1`), and the module header comment (`Wsl.Helpers.ps1`).
  `kali` and the generic `cdwsl [distro]` remain for jumping into any WSL distro.
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
