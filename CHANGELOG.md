# Changelog

All notable changes to this repo. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); this is a personal dotfiles repo,
so entries are grouped by theme rather than strict semver releases.

## [Unreleased] — DX/UX overhaul

A structural + terminal-UX pass focused on a world-class bootstrap and shell
experience. Grouped by the audit IDs that drove the work.

### CI / structure (backend)

- **Hermetic, incremental CI** — GitHub Actions pinned to commit SHAs; Pester and
  PSScriptAnalyzer pinned to exact versions; PSGallery modules cached; a
  `detect-changes` gate skips the Windows jobs for docs-only changes. _(B1–B3)_
- **Coverage gate** — Pester enforces ≥85% coverage on the pure-helper library. _(B4)_
- **`uninstall.ps1`** — reverse the bootstrap; removes only symlinks that point
  back into the repo, with `-DryRun` / `-RestoreBackups`. _(B5)_
- **Pre-commit hook** — `.githooks/pre-commit` runs the dependency-free validator;
  `install.ps1` wires `core.hooksPath`. _(B6)_
- **Fragment-load health gate** — the profile records any fragment that fails to
  load; `dotfiles-doctor` reports it. _(B7)_
- **More host-layer tests** — extracted pure helpers (`ConvertTo-WslPath`,
  `Get-FragmentHealthResult`, the uninstall link map) with behavioral tests. _(B8)_
- **Pinned module floors** — `packages/modules.ps1` carries `-MinimumVersion`
  floors for a reproducible baseline without freezing maintenance updates. _(B9)_
- **Dependabot** for the pinned actions. _(B10)_
- **Install transcript log** under `%LOCALAPPDATA%\dotfiles\logs`. _(B11)_
- **editorconfig enforcement** (final newline / trailing whitespace / LF) in the
  validator and Pester suite. _(B12)_
- **Manifest provenance** — winget ids must be `Publisher.Package`; scoop apps
  must name a declared bucket. _(B13)_
- This changelog. _(B14)_

### Terminal UX

- **`install.ps1 -DryRun`** previews every change and mutates nothing; `-Help`
  prints usage; `-NonInteractive` / `-Yes` for unattended runs. _(U1, U8)_
- **Graceful interrupts** — `install.ps1` and the package installer print where
  they stopped (and close the log) on Ctrl-C or error. _(U2)_
- **Unified error/warning layout** — `Write-DotErr` / `Write-DotWarn` used across
  the entry points. _(U3)_
- **`NO_COLOR` + `DOTFILES_ASCII`** fallbacks across every renderer. _(U4)_
- **Install progress** — per-package `[n/total]` with elapsed time. _(U5)_
- **Interactive overwrite** — confirm before backing up a real user file; stale
  links are rewired silently. _(U6)_
- **Tab-completion** for `dothelp` filters, derived from the catalog. _(U7)_
- **Zero-config onboarding** — prompt for git name/email at install time. _(U9)_
- **`dotfiles-doctor -Fix`** opt-in remediation for the common issues. _(U10)_
- **`dothelp -i`** fuzzy command picker (fzf) that copies the pick. _(U11)_
