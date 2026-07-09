---
description: Go/no-go readiness check before a deliberate dotfiles-Windows release — recommends the next version
argument-hint: "[target version X.Y.Z — optional]"
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git describe:*)
---

# /release-readiness

Answer ONE question: **is dotfiles-Windows due a deliberate release, and if so, what
version?** This reports; it never tags.

Target for this run: **$ARGUMENTS** (empty = infer the next version from the
unreleased work).

## How Windows versions (the wrinkle that makes this routine useful)

`auto-tag.yml` **auto-PATCH-bumps** on every push to `main` that touches `nvim/**`
or `starship/**` — i.e. when the mirror-sync bots land new Core-mirrored content. So
the tag line advances **mechanically** and routinely runs **ahead of the
`CHANGELOG.md` headings** (e.g. tags at `v1.1.6` while the last `## [vX.Y.Z]` heading
is `v1.1.0`). A `feat`/`perf`/breaking change to the *host* (PowerShell profile &
modules, Windows Terminal, packages, psmux, the WSL bridge) accumulates in
`[Unreleased]` and never earns more than a patch **unless a human cuts it
deliberately** and promotes the CHANGELOG heading. Recognizing that moment is this
routine's job. (Windows is a leaf — it vendors no `core/` and isn't vendored — so a
release fans out to nothing.)

## The readiness checklist (gather, then judge)

1. **What's actually unreleased, and is it mechanical or meaningful?** Because
   auto-tag's patch tags run ahead of the human-facing headings, anchor on the **last
   `## [vX.Y.Z]` heading** in `CHANGELOG.md`, not the last tag: find that version, then
   `git log <that-tag>..HEAD --oneline` for everything since the last *deliberate*
   release. Cross-check against `[Unreleased]` — meaningful commits not yet reflected
   there (e.g. a `perf`/`feat` that shipped inside a mechanical patch tag) are
   themselves a finding. Also grab the last tag (`git describe --tags --abbrev=0`) for
   the coherence check in step 3. **Separate** the mechanical churn (`sync
   nvim/starship…`, `chore(packages)`, `ci`) — which auto-tag's patch already covers —
   from the **meaningful host work** (`feat`, `perf`, a real `fix`, a breaking
   module/profile change).
2. **Does the content exceed a patch?** Propose the next SemVer from the *meaningful*
   content:
   - a **breaking** host change (a removed/renamed module export, a changed profile
     contract, a `feat!`/`BREAKING CHANGE`) → **major**
   - a `feat`/`perf` (a new command, a real UX/perf improvement) → **minor**
   - only `fix`/`chore`/`ci`/mirror-syncs → **patch** (auto-tag already handles this —
     verdict "hold, nothing deliberate to cut").
3. **CHANGELOG ↔ tag coherence.** If the last tag is **ahead** of the last
   `## [vX.Y.Z]` heading, the CHANGELOG is behind the mechanical patches — the next
   deliberate release should reconcile them: promote `[Unreleased]` under the
   recommended `## [vX.Y.Z]` heading so the human-facing history catches up to the tag
   line.

## How to report

A one-line **verdict** up top — **READY to cut vX.Y.Z** or **HOLD (only mechanical
patches — let auto-tag handle it)** — then:

- **What would ship** — the *meaningful* `[Unreleased]` highlights (the release's
  story), with the mechanical churn summarized in one line, not enumerated.
- **Proposed version + why** — the SemVer the meaningful content implies, naming the
  single commit/entry that drives the bump (esp. anything breaking), and noting how
  far the tag line has drifted ahead of the CHANGELOG.
- **Next step** — when READY: promote `[Unreleased]` under `## [vX.Y.Z] - <today>` in
  `CHANGELOG.md` and cut the `vX.Y.Z` tag deliberately (a minor/major auto-tag won't
  produce on its own). When HOLD: say so — the mirror-sync patches are fine as-is.

Report only — do **not** edit `CHANGELOG.md` or cut a tag. The maintainer drives the
release from here.
