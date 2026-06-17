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
| B10 | ⬜ | Bootstrap flow | Requires manual `git clone` + `.\install.ps1`; no integrity-gated one-liner. | Hash-pinned `irm <url> \| iex` that clones then runs `install.ps1`, honoring the existing `DOTFILES_*` supply-chain gates. | Medium |
| B11 | ⬜ | `30-windows.ps1` `modules-localize` | `robocopy /E` copies modules off OneDrive but leaves originals and never prunes the local dir against the pinned set. | Reconcile the local module dir to the pinned set (prune extras); record applied state. | Medium |
| B12 | ✅ | `ci.yml` lua-lint | `luacheck` was apt/luarocks-installed **unpinned** every run — slow, non-hermetic, a supply-chain gap vs. the SHA-pinned Actions. | Pin `LUACHECK_VERSION`, cache the compiled rock keyed on runner image + Lua line, and install against Lua 5.1. _(PR #13)_ | Medium |

## Terminal UX

| ID | Status | Component | Problem | Direction | Impact |
| -- | ------ | --------- | ------- | --------- | ------ |
| U1 | 🟡 | `05-lib.ps1` renderers | `gum` is installed but only the **confirm** path uses it ✅; spinner/banner/rule/error are still hand-rolled. | Route `Invoke-DotSpinner`→`gum spin`, banners/rules→`gum style`/`gum format`, keeping pure fallbacks when gum/NO_COLOR absent. | High |
| U2 | ⬜ | `Install-Packages.ps1` | Progress is indeterminate (`[n/total]` + final seconds); no overall bar/ETA over a multi-minute install. | Determinate overall bar (gum or one `Write-Progress`) with `n/total` + ETA. | Medium |
| U3 | ⬜ | install / packages | No interactive selection; optional groups are undiscoverable env-flag opt-ins. | First run uses `gum choose --no-limit` to pick optional groups; persist to `local.ps1`. | Medium |
| U4 | ✅ | `45-doctor.ps1` | Flat result list, no machine-readable mode. | Grouped sections (pure `Get-DoctorGroup`) + `-Json`. _(PR #8)_ | Medium |
| U5 | 🟡 | `05-lib.ps1` `Write-DotRule`, `dothelp` | Rule width hardcoded; renderers didn't adapt to terminal width. | `Get-DotConsoleWidth`-driven rules/hints ✅; width-aware help/doctor tables still partial. _(PR #8)_ | Medium |
| U6 | ⬜ | `05-lib.ps1` | Color is binary on/off over the 16-color `ConsoleColor` enum; accents can't match the Tokyo Night palette. | Detect `COLORTERM=truecolor`; emit 24-bit ANSI for accents (fall back to ConsoleColor). | Medium |
| U7 | ✅ | `05-lib.ps1` `Invoke-DotSpinner` | Ctrl-C could orphan the background job around the `Start-Job`/try seam. | Track the job in script scope, clean in `finally`; ThreadJob is cheaper to abort. _(PR #7)_ | High |
| U8 | ✅ | `profile.ps1` degraded-load nudge | Only the count + first failure printed inline. | Name all failing fragments + the one-command fix inline. _(PR #7)_ | Medium |
| U9 | ⬜ | `55-help.ps1` `dothelp -i` | The fzf picker hides the preview, so description/group columns are unused while choosing. | Show description+group in an `fzf --preview` (or `gum filter`). | Medium |
| U10 | ✅ | `profile.ps1` / `00-aliases.ps1` | A half-provisioned box silently lost `ls`/`cat`/`z` with no hint. | Throttled once-per-session "N core tools missing — run dotfiles-doctor" (`57-health-nudge.ps1`). _(PR #7)_ | High |
| U11 | ⬜ | `install.ps1` / lib | Only the email loop is validated; other `Read-Host` calls share no validation/default/masking pattern. | Shared `Read-DotInput` with validation + default + `gum input --password` for secrets. | Medium |
| U12 | ✅ | `05-lib.ps1` renderers | Hint lines weren't wrapped; long paths overflowed. | Word-wrap hints to width (`Format-DotWrap`). _(PR #8)_ | Medium |
| U13 | ⬜ | `Install-Packages.ps1` | During the longest silent ops the spinner label is static — stalled vs. slow is indistinguishable. | Tick the spinner title with running elapsed seconds. | Medium |

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
