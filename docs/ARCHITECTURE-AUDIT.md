# ARCHITECTURE-AUDIT.md — DX / UX / boundary backlog

A living tracker for the architecture / developer-experience / terminal-UX audit
of this repo. It exists so the backlog stops living in PR descriptions and chat:
each item has a stable ID, an impact, and a status, and PRs reference the ID.

**Status legend:** ✅ shipped · 🟡 partial · ⬜ open

> Namespace note: these `B#`/`U#` IDs are the **audit** namespace. They are
> distinct from the `B1–B14` / `U1–U11` headings in `CHANGELOG.md`, which track
> the earlier structural pass. Reconciling the two namespaces is itself a
> long-tail item (see below).

## Backend / boundary architecture

| ID | Status | Component | Problem | Direction | Impact |
| -- | ------ | --------- | ------- | --------- | ------ |
| B1 | 🟡 | `nvim-sync.ps1`, parity prose | One-way `robocopy /MIR`, no recorded source ref, no drift detection — parity can silently rot. | Record synced Core SHA (`nvim/.core-ref`) ✅; CI parity gate ✅ — `tests/Assert-NvimParity.ps1` clones Core @ the recorded commit and diffs `nvim/` (excluding `lazy-lock.json`/`.core-ref`), failing on drift and self-skipping until a sync stamps the ref; pure helpers unit-tested. Remaining ⬜: an option to pin `nvim-sync` to a specific ref for a reproducible re-vendor. | High |
| B2 | ✅ | `10-tools.ps1` `Get-InitCache` | Cache busted only on binary mtime; editing generator flags left a stale cache. | Key on SHA-256(generator text) + tool mtime so a flag change self-invalidates. _(PR #7)_ | High |
| B3 | ✅ | `05-lib.ps1` `Invoke-DotSpinner` | `Start-Job` spawned a child pwsh per spinner. | `Start-ThreadJob` with `Start-Job` fallback. _(PR #7)_ | Medium |
| B4 | 🟡 | `packages/*` | Only PS modules were version-pinned; scoop/winget apps floated to latest, so two boxes diverge — "reproducible" was partial. | Lockfile machinery shipped ✅: pure `PackageLock.ps1` (read/parse-export/drift), an `Update-PackageLock.ps1` generator, `Install-Packages.ps1 -Frozen` (installs exact `packages.lock.json` versions, skips un-locked apps rather than floating), and a CI drift gate (skipped until the lock exists). Remaining ⬜: run the generator on a Windows box and commit `packages.lock.json` — that arms the drift gate and makes `-Frozen` reproduce a real baseline. | High |
| B5 | 🟡 | `.github/workflows/ci.yml` | Coverage gate measured only `05-lib.ps1`; the other pure-helper files (incl. the new `Dotfiles/*.Helpers.ps1`) were tested but **ungated**. | `CodeCoverage.Path` expanded to the whole pure-helper surface ✅ _(PR #13)_; the `minTotal`/`minFiles` floors were bumped for the new suites but remain hand-maintained — a generated/checked-in baseline is still ⬜. | Medium |
| B6 | ✅ | `profile.ps1` loader | Fragment order/deps were implicit (`NN-` sort + shared globals); no declared contract. | Per-fragment `provides`/`requires` headers + `LoadContract.Tests.ps1`, which derives the dependency graph from the AST and asserts every requirement resolves to the module or a strictly-earlier fragment. _(PR #14)_ | Medium |
| B7 | ✅ | All fragments | Nearly every helper was `global:`, polluting the session with no teardown. | Profile's pure surface wrapped in a `Dotfiles` module exporting a curated set; only intended verbs stay global. _(PRs #9–#12 + scope tidy)_ | High |
| B8 | ✅ | `install.ps1` transcript, `40-op.ps1` | Transcript captured the whole run unredacted; logs never pruned. | Redact via `Test-SensitiveHistoryLine`; cap `install-*.log` at 10. _(PR #7)_ | Medium |
| B9 | ✅ | `install.ps1` / `uninstall.ps1` / `Install-Packages.ps1` | Backslash literals in the **script-loading** `Join-Path` calls that dot-source `05-lib.ps1` — a cross-platform footgun if a bootstrap script is run under Linux pwsh. | All three bootstrap lib-loads normalized to forward slashes ✅ _(install/uninstall PR #13; Install-Packages follow-up)_. Windows-only **runtime data** paths (`$env:LOCALAPPDATA\…`, `Documents\PowerShell\Modules`, cache dirs) keep the backslash house style by design — they're only evaluated on Windows hosts / Windows-specific entrypoints (`os/*` fragments, the installer's package step), not under the Linux pwsh that runs the fast CI gate. | Medium |
| B10 | ✅ | `bootstrap.ps1` | Setup required a manual `git clone` + `.\install.ps1`; no integrity-gated one-liner. | A self-contained `bootstrap.ps1` (`irm … \| iex`) clones-or-updates the repo, optionally checks out a pinned `DOTFILES_REF`, and hands off to `install.ps1` — it never pipes a further network script into `iex`, so scoop stays behind the existing `DOTFILES_SCOOP_SHA256` gate and every `DOTFILES_*` env knob is inherited untouched. README documents a hash-verified one-liner; a drift test pins the README's LF-normalized SHA-256 to the script. Pure resolvers (`Get-Bootstrap{RepoUrl,TargetDir,GitAction,InstallArgs}`) unit-tested. | Medium |
| B11 | ✅ | `30-windows.ps1` `modules-localize` | `robocopy /E` copied modules off OneDrive but never reaped the stale versions each maintenance roll-forward left behind, so the local dir accumulated. | `modules-localize -Prune` reconciles the local dir against the MANAGED set (`packages/modules.ps1`): keep the highest version of each managed module, remove older ones, never touch a non-managed module. The decision is the pure, coverage-gated `Get-DotModulePrunePlan` (Dotfiles module export, unit-tested); the prune is idempotent and reports each removal. | Medium |
| B12 | ✅ | `ci.yml` lua-lint | `luacheck` was apt/luarocks-installed **unpinned** every run — slow, non-hermetic, a supply-chain gap vs. the SHA-pinned Actions. | Pin `LUACHECK_VERSION`, cache the compiled rock keyed on runner image + Lua line, and install against Lua 5.1. _(PR #13)_ | Medium |

## Terminal UX

| ID | Status | Component | Problem | Direction | Impact |
| -- | ------ | --------- | ------- | --------- | ------ |
| U1 | 🟡 | `05-lib.ps1` renderers | `gum` was installed but only the **confirm** path used it. | gum now covers the interactive prompts — `confirm` ✅ and `input` ✅ (U11). The remaining renderers are deliberately NOT routed through gum: `gum spin` wraps an external command and can't run our object-returning scriptblock without re-introducing the process spawn B3 removed; there's no clean gum primitive for the titled `Write-DotRule`; and a `gum style` banner is a marginal change for a subprocess-per-banner cost. So spinner/rule/banner stay hand-rolled (with their pure NO_COLOR/ASCII fallbacks). | High |
| U2 | ✅ | `Install-Packages.ps1` | Progress was indeterminate (per-phase `[n/total]` + final seconds); no overall sense of how far / how much longer over a multi-minute install. | A single determinate `Write-Progress` bar spanning all three phases (scoop + winget + modules), updated per item with `done/total` and an ETA extrapolated from the average pace. The model is the pure, unit-tested `Get-DotInstallProgress` + `Format-DotDuration`; the bar renders only on a live console (skipped under NO_COLOR/redirected/CI, where the per-item log carries the detail) and clears in `finally` (on completion AND Ctrl-C). | Medium |
| U3 | ✅ | install / packages | No interactive selection; nothing was discoverable or skippable. | Manifest entries carry an optional `group` tag (`gui` = Firefox/Obsidian/1Password); the first interactive run picks groups with `gum choose --no-limit` (opt-out: all preselected) and persists `DOTFILES_PKG_GROUPS` to `local.ps1`, so later/CI runs don't re-prompt. Pure policy (`Get-DotOptionalGroups`/`ConvertFrom`/`ConvertTo-DotGroupList`/`Test-DotGroupSelected`/`Set-DotGroupLine`) is unit-tested; non-interactive installs every group (zero regression). | Medium |
| U4 | ✅ | `45-doctor.ps1` | Flat result list, no machine-readable mode. | Grouped sections (pure `Get-DoctorGroup`) + `-Json`. _(PR #8)_ | Medium |
| U5 | ✅ | `05-lib.ps1` `Write-DotRule`, `dothelp`, `45-doctor.ps1` | Rule width hardcoded; renderers didn't adapt to terminal width. | `Get-DotConsoleWidth`-driven rules/hints ✅ _(PR #8)_; the `dothelp` description column and the doctor **detail** column now word-wrap to the console via `Format-DotWrap`, continuation lines aligned under their column (matching the doctor hint already did). Falls back to 80 cols when there's no console (CI/redirected), so short entries are unchanged. | Medium |
| U6 | ✅ | `05-lib.ps1` | Color was binary on/off over the 16-color `ConsoleColor` enum; accents couldn't match the Tokyo Night palette. | `Test-DotTrueColor` (COLORTERM=truecolor/24bit + a `[Console]::IsOutputRedirected` guard so ANSI never leaks into captured/CI streams) and a pure `Get-DotAnsiSgr` (ConsoleColor name → 24-bit Tokyo Night SGR) wired into `Write-DotHost`/`Write-DotBanner` — every existing `-Color` call auto-upgrades on a live truecolor terminal and falls back to ConsoleColor everywhere else. Pure helpers unit-tested. | Medium |
| U7 | ✅ | `05-lib.ps1` `Invoke-DotSpinner` | Ctrl-C could orphan the background job around the `Start-Job`/try seam. | Track the job in script scope, clean in `finally`; ThreadJob is cheaper to abort. _(PR #7)_ | High |
| U8 | ✅ | `profile.ps1` degraded-load nudge | Only the count + first failure printed inline. | Name all failing fragments + the one-command fix inline. _(PR #7)_ | Medium |
| U9 | ✅ | `55-help.ps1` `dothelp -i` | The fzf picker hid the preview, so the description/group columns were unused while choosing. | `Get-DotHelpFlatLines` now renders an aligned `command   description   [group]` display column (in PowerShell) with the bare command in a hidden trailing field; the picker shows the display (`--with-nth 1`, `--nth 1`) and extracts the command from the last field on pick. Rendering in PowerShell — rather than a `--preview 'echo …'` shell — is deliberate: catalog cells like `mkbak <f>` and groups like `Listing & files` carry cmd.exe metacharacters (`< > &`) a preview shell would mis-parse (caught in review). Unit-tested, incl. the metacharacter cases. | Medium |
| U10 | ✅ | `profile.ps1` / `00-aliases.ps1` | A half-provisioned box silently lost `ls`/`cat`/`z` with no hint. | Throttled once-per-session "N core tools missing — run dotfiles-doctor" (`57-health-nudge.ps1`). _(PR #7)_ | High |
| U11 | ✅ | `install.ps1` / lib | Only the email loop was validated; other `Read-Host` calls shared no validation/default/masking pattern. | Shared `Read-DotInput` (gum `input` when interactive, else `Read-Host`; optional validator, default, and `--password`/`-MaskInput` secret masking) over a pure, unit-tested `Get-DotInputResult`. install's git name/email prompts now use it; `-Secret` is ready for token prompts. | Medium |
| U12 | ✅ | `05-lib.ps1` renderers | Hint lines weren't wrapped; long paths overflowed. | Word-wrap hints to width (`Format-DotWrap`). _(PR #8)_ | Medium |
| U13 | ✅ | `Install-Packages.ps1` / lib | During the longest silent ops the spinner label was static — stalled vs. slow was indistinguishable. | `Invoke-DotSpinner` now ticks a running `(Ns)` elapsed counter (stopwatch-driven) onto the label, via a pure, unit-tested `Format-DotSpinnerLine` (suffix appears only past 1s, so quick ops don't flash `(0s)`); the line-wipe tracks the widest frame so a grown counter clears cleanly. | Medium |

## Secondary long-tail (~15–25 items, lower impact)

Not yet itemized with IDs; recorded here so they aren't lost:

- **Config files not deeply reviewed** — `starship.toml`, `windows-terminal/settings.json`, `psmux/*.conf`, `ssh/config`, `git/.gitconfig` (~5–8 small findings: theme/font/keybind drift, hardcoded values, comment hygiene).
- **Test-suite refinements** — assertion depth, fixture duplication, the brittle CI floors (overlaps B5) (~4–6).
- **Docs drift** — README layout box vs. actual fragments (`25`/`45`/`50`/`55`), `TOOLS.md` / `PORTING-NOTES.md` currency (~3–4).
- **Micro-consistencies** — stray `Write-Host` vs `Write-DotHost`, `nvim-sync` Windows-keymap wart, `serve` binding all interfaces, alias/function naming parity (~3–5).
- **Namespace reconciliation** — unify the audit `B#`/`U#` IDs with `CHANGELOG.md`'s separate `B#`/`U#` headings so a reader isn't tracking two collide-numbered schemes.

---

_Maintained as part of the architecture audit. When an item ships, flip its
status and cite the PR; when a new structural issue is found, give it the next
free ID in its section._
