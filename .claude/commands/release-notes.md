---
description: Draft the next dotfiles-Windows release's CHANGELOG entry from Conventional Commits (report-first)
argument-hint: "[from-ref — optional, defaults to the last CHANGELOG version heading]"
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git describe:*)
---

# /release-notes

Draft the `CHANGELOG.md` entry for the next deliberate release from its Conventional
Commits — the report-first preview a maintainer curates into `[Unreleased]` before
cutting. Complements `/release-readiness` (which decides *whether* + *what version*);
this drafts *what goes in it*.

Range for this run: **$ARGUMENTS** (empty = since the last **CHANGELOG version
heading**, not just the last tag — see below; otherwise `$ARGUMENTS..HEAD`).

## Resolve the range (mind the auto-patch drift)

Windows' `auto-tag` patch-bumps on nvim/starship mirror-syncs, so the last **tag**
(`git describe --tags --abbrev=0`) often runs ahead of the last **`## [vX.Y.Z]`
heading** in `CHANGELOG.md`. For release notes you want everything since the last
*human-facing* release, so default the range to the commit of the **last CHANGELOG
version heading** → `HEAD` (fall back to the last tag only if the two align). Read
`CHANGELOG.md`'s `[Unreleased]` too — it's the curated half of the same story.

## How to draft

1. `git log <range> --no-merges --format='%s%n%b'` for the commit subjects/bodies.
2. **Group by Conventional-Commit type into Keep-a-Changelog sections**, skipping any
   empty one:
   - `feat:` → **Added** (or **Changed** if it modifies existing behavior)
   - `perf:` → **Changed** (call out the improvement)
   - `fix:` → **Fixed**
   - a removed/renamed module export or profile contract, or `feat!`/`BREAKING
     CHANGE:` → **Removed** / **Changed**, flagged **breaking**
   - **Fold the mechanical churn** — `sync nvim/starship…`, `chore(packages)`, `ci` —
     into a single terse line (e.g. "Housekeeping: Core mirror-syncs + package
     re-pins") or omit; don't enumerate it as user-facing news.

## How to report

- **A ready-to-curate block** — a `## [vX.Y.Z] - <today>` heading (use the version
  `/release-readiness` recommends, or `vX.Y.Z` as a placeholder) with grouped bullets
  in Keep-a-Changelog style, ready to paste under `[Unreleased]`.
- **An editorial pass** — user-facing vs internal plumbing, anything **breaking**
  (surface it loudly — it drives the major bump), and a one-line **release headline**.

`CHANGELOG.md` prose is hand-curated (the *rationale* for a change, not its commit
subject), so treat the generated bullets as **raw material** — a scaffold to curate,
not a drop-in. Report only — do **not** edit `CHANGELOG.md` or cut a tag.
