# ============================================================================
#  nvim-sync.ps1  -  vendor nvim/ from dotfiles-nvim (standalone; NO subtree)
#
#  dotfiles-Windows is a STANDALONE repo. It does not vendor Core as a subtree,
#  because PowerShell can't consume Core's zsh/tmux/bash layers — the only shared
#  asset worth having on the host is the Neovim Lua tree.
#
#  THE EDITOR NO LONGER COMES FROM CORE. dotfiles-core's NVIM-SPLIT-PROPOSAL.md
#  (DECIDED — A2) extracted nvim/ into dotgibson/dotfiles-nvim, which owns the
#  editor: its own gate (headless startup, :checkhealth, luacheck against a real
#  Neovim — none of which Core's runners could do), its own release line, its own
#  plugin-pin cadence. Core now VENDORS that repo behind an nvim.lock, and so does
#  this one. §3.1 called this repo the tell: it always consumed the editor alone
#  through a bespoke mirror, pinned to a Core ref that had nothing to do with when
#  the editor changed. Pointing the same script at one different URL turns the side
#  channel into the front door — a first-class second consumer of a real release
#  line, on the same pin shape Core itself uses (dotfiles-core#1124).
#
#  Usage (from the repo root):
#    .\nvim-sync.ps1                                  # pin the newest vX.Y.Z release
#    .\nvim-sync.ps1 -Ref v1.2.0                      # pin an exact release/commit
#    .\nvim-sync.ps1 -FollowBranch                    # track main's tip instead
#    .\nvim-sync.ps1 -NvimLocal C:\src\dotfiles-nvim  # copy from an existing clone
#
#  A BARE RUN PINS A RELEASE, not a branch tip, and that is the behaviour change
#  this repo made when it stopped following Core (it used to track Core's main).
#  dotfiles-nvim publishes releases precisely so its consumers can name one, and a
#  release is the unit its gate signs off on. -FollowBranch is for checking what is
#  coming, not for pinning.
#
#  After it runs: review `git diff nvim/ nvim.lock`, then commit BOTH in one commit
#  — a window where the tree has moved and the pin has not reads as drift to the
#  parity gate and is indistinguishable from a hand-edit. lazy-lock.json IS synced
#  (it pins plugin commit SHAs, which are cross-platform — same as the Unix fleet).
# ============================================================================
[CmdletBinding()]
param(
    [string]$NvimRemote = 'https://github.com/dotgibson/dotfiles-nvim.git',
    [string]$Branch     = 'main',
    [string]$NvimLocal,
    # Pin an EXACT commit/tag for a reproducible re-vendor. Takes precedence over
    # the default release resolution; can't be combined with -NvimLocal (which
    # copies a local working tree as-is). Validated by Get-NvimSyncRefPlan.
    [string]$Ref,
    # Track $Branch's tip instead of the newest release. Explicit on purpose: it
    # used to be the default, and silently vendoring unreleased editor commits is
    # exactly what pinning a release line is meant to stop.
    [switch]$FollowBranch
)

# --- Get-NvimSyncRefPlan ------------------------------------------------------
# Pure: decide what to fetch — a pinned -Ref, an explicit -FollowBranch tip, a
# local clone, or (the default) the newest published release — and reject the
# illegal combinations up front. Returns { Mode = 'ref'|'branch'|'release'|'local';
# Target; Label }. In 'release' mode Target is empty: it is not knowable without
# asking the remote, which Get-LatestNvimRelease does. Unit-tested via the
# DOTFILES_NVIMSYNC_LIBONLY hook below.
function Get-NvimSyncRefPlan {
    [OutputType([pscustomobject])]
    param([string]$Ref, [string]$Branch = 'main', [string]$NvimLocal, [switch]$FollowBranch)
    if ($Ref -and $Ref.StartsWith('-')) {
        throw "invalid -Ref '$Ref': a git ref cannot start with '-'."
    }
    if ($Ref -and $NvimLocal) {
        throw '-Ref re-vendors from the remote and cannot be combined with -NvimLocal. Check out the ref in your local clone and pass -NvimLocal alone, or drop -NvimLocal to fetch the pinned ref.'
    }
    if ($Ref -and $FollowBranch) {
        throw '-Ref pins one revision and -FollowBranch tracks a moving tip; pass one or the other.'
    }
    if ($NvimLocal) { return [pscustomobject]@{ Mode = 'local'; Target = $NvimLocal; Label = "local clone $NvimLocal" } }
    if ($Ref) { return [pscustomobject]@{ Mode = 'ref'; Target = $Ref; Label = "pinned ref $Ref" } }
    if ($FollowBranch) { return [pscustomobject]@{ Mode = 'branch'; Target = $Branch; Label = "branch $Branch (tip)" } }
    return [pscustomobject]@{ Mode = 'release'; Target = ''; Label = 'newest vX.Y.Z release' }
}

# --- Get-LatestNvimRelease ----------------------------------------------------
# Pure: pick the newest release tag out of `git ls-remote --tags --refs` output.
# Returns '' when the remote publishes none, which the caller turns into a clear
# error rather than a silent fall-back to a branch tip.
#
# THE SHAPE FILTER IS THE WHOLE POINT, and it is the same one dotfiles-core's
# scripts/check-nvim-freshness.sh and scripts/fleet-drift.sh apply, for the same
# reason: a pin must never be measured against — or set to — a tag that MOVES.
# dotfiles-nvim's release workflow cuts `v1.0.0` and then re-points a major alias
# `v1` at it (Core's tag-release.sh shape). Requiring all three numeric fields and
# anchoring at both ends excludes the alias by construction, and drops prereleases
# (`v1.1.0-rc1`) with the same anchor. `--refs` is what strips the peeled `^{}`
# rows, so the caller must pass it.
#
# Ordering is a three-field NUMERIC compare, never a string sort: `v1.9.0` sorts
# after `v1.10.0` lexically, and that silently pins the wrong release. (The Unix
# side says the same thing as "no sort -V" — there it is also a portability point;
# here PowerShell has no sort -V to reach for, only the trap.)
function Get-LatestNvimRelease {
    [OutputType([string])]
    param([string[]]$LsRemoteLine)
    $bestParts = $null
    $best = ''
    foreach ($line in $LsRemoteLine) {
        if ("$line" -notmatch '^[0-9a-f]{40}\s+refs/tags/v([0-9]+)\.([0-9]+)\.([0-9]+)$') { continue }
        $parts = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
        $newer = $null -eq $bestParts
        if (-not $newer) {
            foreach ($i in 0, 1, 2) {
                if ($parts[$i] -gt $bestParts[$i]) { $newer = $true; break }
                if ($parts[$i] -lt $bestParts[$i]) { break }
            }
        }
        if ($newer) { $bestParts = $parts; $best = "v$($parts[0]).$($parts[1]).$($parts[2])" }
    }
    $best
}

# --- Get-NvimRepoSlug ---------------------------------------------------------
# Pure: the `owner/name` form of a GitHub remote, which is what nvim.lock records
# (dotfiles-core's nvim.lock spells nvim_repo the same way). '' for anything that
# is not a recognisable GitHub URL — a local path, a mirror — and the caller then
# keeps the canonical slug, because the REPOSITORY is dotgibson/dotfiles-nvim no
# matter which transport the bytes arrived over. That distinction matters: the
# parity gate re-clones from the slug to verify, so the slug has to name a repo
# that actually publishes the recorded commit.
function Get-NvimRepoSlug {
    [OutputType([string])]
    param([string]$Remote)
    if ("$Remote" -match '^(?:https://github\.com/|git@github\.com:)([^/]+)/([^/]+?)(?:\.git)?/?$') {
        return "$($Matches[1])/$($Matches[2])"
    }
    ''
}

# --- Write-NvimLockFile -------------------------------------------------------
# Write nvim.lock with explicit LF and no BOM. `Set-Content -Encoding UTF8` writes
# CRLF on Windows, so every sync left the working tree with CRLF that .gitattributes
# then silently normalized on commit. Write the bytes we actually mean.
# (Body kept identical to starship-sync.ps1's Write-CoreRefFile — the scripts are
# deliberate twins; only the file this one writes has a different name and shape.)
function Write-NvimLockFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(ValueFromPipeline)][string[]]$Line
    )
    begin { $acc = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($l in $Line) { $acc.Add($l) } }
    end {
        [System.IO.File]::WriteAllText($Path, (($acc -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    }
}

# --- Get-NvimDescribeTag ------------------------------------------------------
# Nearest RELEASE tag describing $Rev in $RepoPath — 'v1.0.0' when the vendored
# commit IS a release, 'v1.0.0-3-gabc1234' a few commits past one. Empty (and the
# nvim_tag line then left blank) when nothing matches: the clone is still shallow
# past the nearest tag, or -NvimLocal isn't a git repo at all. Only -FollowBranch
# and a non-tag -Ref reach it; a release-mode run already knows its tag.
#
# --match 'v[0-9]*.[0-9]*.[0-9]*' IS LOAD-BEARING, not tidiness (#202; ports the
# same fix from dotfiles-core#515 / sync-core.sh). Every release ALSO carries a
# moving major alias (`v1`), re-pointed on each cut with `git tag -fa` AFTER the
# specific tag. Both are annotated and both sit on the release commit, so
# `git describe` breaks the tie by TAGGER TIME and prefers the alias. That is how
# the old nvim/.core-ref came to record `tag = v4-19-g10ad221`: a provenance field
# naming a target that moves out from under it, so the same recorded string means a
# DIFFERENT commit after the next release. The two-dot shape excludes the alias by
# construction. (It also immunizes a -NvimLocal run against a locally STALE alias —
# a plain `git fetch` never force-updates an existing tag.)
#
# Don't "simplify" by dropping --tags: that restricts describe to annotated tags,
# and the alias is annotated too, so it would fix nothing.
#
# The single-quoted glob reaches git VERBATIM: PowerShell does not expand wildcards
# in native-command arguments (that is a POSIX shell behaviour); the quotes only
# stop its own parser from reading `[`, `]` and `*`.
#
# try/catch, not `2>$null` alone: today $PSNativeCommandUseErrorActionPreference is
# $false, so a failing git yields $null instead of throwing under this script's
# ErrorActionPreference='Stop'. If a future pwsh flips that default, the redirect on
# its own would stop protecting the contract and a tag-less source would abort the
# whole sync. The contract is "best-effort, never fatal" — state it rather than
# inherit it. (Kept identical in starship-sync.ps1's Get-CoreDescribeTag.)
function Get-NvimDescribeTag {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string]$Rev = 'HEAD'
    )
    try { $t = (& git -C $RepoPath describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' $Rev 2>$null) }
    catch { return '' }
    if ($t) { "$t".Trim() } else { '' }
}

# Library-only hook for the test suite: expose the helpers without syncing.
if ($env:DOTFILES_NVIMSYNC_LIBONLY -eq '1') { return }

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target   = Join-Path $RepoRoot 'nvim'
$LockFile = Join-Path $RepoRoot 'nvim.lock'
$plan     = Get-NvimSyncRefPlan -Ref $Ref -Branch $Branch -NvimLocal $NvimLocal -FollowBranch:$FollowBranch

$tempClone = $null
try {
    # --- resolve the source nvim tree ----------------------------------------
    if ($plan.Mode -eq 'local') {
        $srcRoot = $NvimLocal
        Write-Host "Using local dotfiles-nvim clone: $srcRoot" -ForegroundColor Cyan
    } else {
        $fetchTarget = $plan.Target
        if ($plan.Mode -eq 'release') {
            # Ask the remote which releases exist, then pin the newest. `--refs`
            # drops the peeled `^{}` rows Get-LatestNvimRelease's anchored pattern
            # would reject anyway, and keeps the parsed set to real refs.
            Write-Host "Resolving the newest release of $NvimRemote ..." -ForegroundColor Cyan
            $lsRemote = (& git ls-remote --tags --refs $NvimRemote 2>$null)
            if ($LASTEXITCODE -ne 0) { throw "git ls-remote '$NvimRemote' failed (exit $LASTEXITCODE) - is the remote reachable?" }
            $fetchTarget = Get-LatestNvimRelease -LsRemoteLine @($lsRemote)
            if (-not $fetchTarget) {
                throw "$NvimRemote publishes no vX.Y.Z release tags - pass -Ref <commit> or -FollowBranch to sync anyway."
            }
            Write-Host "  newest release: $fetchTarget" -ForegroundColor DarkGray
        }
        $tempClone = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-nvim-" + [guid]::NewGuid().ToString('N'))
        if ($plan.Mode -eq 'branch') {
            Write-Host "Shallow-cloning $NvimRemote ($fetchTarget)..." -ForegroundColor Cyan
            git clone --depth 1 --branch $fetchTarget $NvimRemote $tempClone
            if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
        } else {
            # Fetch an EXACT commit/tag shallowly: a --branch clone can't name an
            # arbitrary commit, so init + fetch the ref + detach onto it. GitHub
            # allows fetching a reachable SHA directly. Detaching via FETCH_HEAD is
            # also what PEELS an annotated tag — dotfiles-nvim's releases are
            # annotated (refs/tags/v1.0.0 is the tag object, v1.0.0^{} the commit),
            # and `rev-parse HEAD` after the checkout records the COMMIT, which is
            # the only thing the parity gate can re-fetch.
            Write-Host "Fetching $NvimRemote @ $fetchTarget (pinned)..." -ForegroundColor Cyan
            git init -q $tempClone
            if ($LASTEXITCODE -ne 0) { throw "git init failed (exit $LASTEXITCODE)" }
            git -C $tempClone remote add origin $NvimRemote
            git -C $tempClone fetch --depth 1 origin $fetchTarget
            if ($LASTEXITCODE -ne 0) { throw "git fetch '$fetchTarget' failed (exit $LASTEXITCODE) - is that ref pushed to the remote?" }
            git -C $tempClone checkout -q --detach FETCH_HEAD
            if ($LASTEXITCODE -ne 0) { throw "git checkout FETCH_HEAD failed (exit $LASTEXITCODE)" }
        }
        $srcRoot = $tempClone
    }
    # The payload is the source repo's nvim/ SUBDIRECTORY, not its root:
    # dotfiles-nvim carries its own gate, CI and docs beside the editor tree. Same
    # path Core vendors from, which is why re-pointing this script was a change of
    # URL and not of shape.
    $srcNvim = Join-Path $srcRoot 'nvim'
    if (-not (Test-Path $srcNvim)) { throw "source has no nvim/ tree: $srcNvim" }

    # --- mirror source -> target ----------------------------------------------
    # robocopy /MIR makes the target match the source (so deletions upstream
    # propagate). lazy-lock.json IS mirrored on purpose: it pins each plugin to a
    # commit SHA, and those SHAs are CROSS-PLATFORM — excluding it would leave
    # Windows nvim floating on plugin HEAD while every Unix repo stays pinned.
    # robocopy exit codes 0-7 are success; >=8 is a real error.
    Write-Host 'Syncing nvim/ ...' -ForegroundColor Cyan
    robocopy $srcNvim $Target /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy reported errors (exit $LASTEXITCODE)" }

    # --- record vendoring provenance -> nvim.lock -----------------------------
    # nvim.lock carries dotfiles-core's nvim.lock field names deliberately: this
    # repo and Core are now two consumers of ONE release line, and fleet-drift.sh
    # compares the two pins directly. It lives at the REPO ROOT, not inside nvim/,
    # and that placement is load-bearing three times over: the parity gate compares
    # nvim/ with no exclusion set (it is byte-identical to upstream's), the sync
    # bot judges drift on `git status -- nvim` with no pathspec exclusion, and
    # auto-tag.yml's `nvim/**` trigger cannot see a pin-only change, so a re-pin
    # that moves no editor bytes cuts no release tag.
    #
    # NO nvim_tree FIELD, unlike Core's lock. Core needs one because audit §9q must
    # verify offline with no dotfiles-nvim object store to resolve the pin against.
    # Here tests/Assert-NvimParity.ps1 re-clones at nvim_sha and hash-compares every
    # file, which is strictly stronger — and a git tree hash would not survive a
    # robocopy onto a filesystem that does not carry the exec bit anyway.
    $sha = (& git -C $srcRoot rev-parse HEAD 2>$null)
    # `git describe` needs the tags AND the history back to the nearest one. The
    # clone/fetch above is shallow (--depth 1), where describe sees only a tag
    # sitting ON the tip. For our throwaway temp clone, best-effort deepen + fetch
    # tags so describe resolves the nearest release. (-NvimLocal is the user's OWN
    # clone — don't mutate it; rely on its existing tags.)
    if ($plan.Mode -ne 'local') {
        git -C $srcRoot fetch --tags --unshallow --quiet 2>$null
        # --unshallow errors on an already-complete repo; fall back to a plain fetch.
        if ($LASTEXITCODE -ne 0) { git -C $srcRoot fetch --tags --quiet 2>$null }
    }
    # A release-mode run already resolved its tag and must not re-derive it: describe
    # would hand back the moving `v1` alias's neighbourhood on exactly the commit
    # where the shape filter matters most. An explicit -Ref naming a release is the
    # same case. Everything else asks describe and accepts an empty answer.
    #
    # Don't reorder this with the `git show`-free reads around it: a describe that
    # legitimately finds nothing resets $LASTEXITCODE, and
    # .github/workflows/nvim-sync.yml runs this script under `shell: pwsh`, whose
    # epilogue is `exit $LASTEXITCODE` — that must not turn the bot run red.
    if ($plan.Mode -eq 'release') {
        $tag = $fetchTarget
    } elseif ($Ref -match '^v[0-9]+\.[0-9]+\.[0-9]+$') {
        $tag = $Ref
    } else {
        $tag = Get-NvimDescribeTag -RepoPath $srcRoot -Rev 'HEAD'
    }
    # nvim.version lives at the source repo ROOT, outside the vendored payload —
    # the same file dotfiles-core's scripts/sync-nvim.sh reads for the same field.
    $versionFile = Join-Path $srcRoot 'nvim.version'
    $version = if (Test-Path $versionFile) { (Get-Content $versionFile -TotalCount 1).Trim() } else { '' }
    $slug = Get-NvimRepoSlug -Remote $NvimRemote
    if (-not $slug) { $slug = 'dotgibson/dotfiles-nvim' }
    $now = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    @(
        '# dotfiles-Windows :: vendored editor provenance (written by nvim-sync.ps1)'
        '# ---------------------------------------------------------------------------'
        '# nvim/ IS NOT AUTHORED HERE. It is a vendored copy of dotgibson/dotfiles-nvim,'
        '# which owns the editor: its own gate (headless startup, :checkhealth, luacheck'
        '# against a real Neovim), its own release line, its own plugin-pin cadence. This'
        '# repo vendors no core/ at all, so the editor is the one shared asset it carries'
        '# and this file records WHICH revision of it.'
        '#'
        '# Field names are dotfiles-core/nvim.lock''s on purpose: Core vendors the same'
        '# repo behind the same shape, and scripts/fleet-drift.sh compares the two pins'
        '# directly. Do NOT hand-edit this file or the tree - tests/Assert-NvimParity.ps1'
        '# re-clones at nvim_sha and fails on any difference. Re-run nvim-sync.ps1, and'
        '# commit nvim/ and this file TOGETHER: a window where one moved and the other'
        '# did not is indistinguishable from a hand-edit.'
        '# ---------------------------------------------------------------------------'
        "nvim_repo=$slug"
        "nvim_branch=$Branch"
        "nvim_sha=$(if ($sha) { $sha } else { 'unknown' })"
        "nvim_version=$version"
        "nvim_tag=$tag"
        "synced=$now"
    ) | Write-NvimLockFile -Path $LockFile

    # The pin moved out of nvim/ (dotfiles-core#1124). Clear the old marker so a
    # tree carrying both never reaches the parity gate, which no longer excludes it.
    $legacyRef = Join-Path $Target '.core-ref'
    if (Test-Path $legacyRef) { Remove-Item $legacyRef -Force }

    $shortSha = if ($sha) { $sha.Substring(0, [Math]::Min(7, $sha.Length)) } else { 'unknown' }
    Write-Host "  recorded provenance -> nvim.lock ($(if ($tag) { $tag } else { 'untagged' }) @ $shortSha)" -ForegroundColor DarkGray

    Write-Host ''
    Write-Host 'nvim/ synced from dotfiles-nvim. Review and commit BOTH paths:' -ForegroundColor Green
    Write-Host "  git -C `"$RepoRoot`" diff --stat nvim/ nvim.lock" -ForegroundColor DarkGray
    Write-Host "  git -C `"$RepoRoot`" add nvim nvim.lock ; git -C `"$RepoRoot`" commit -m 'sync nvim from dotfiles-nvim'" -ForegroundColor DarkGray
}
finally {
    if ($tempClone -and (Test-Path $tempClone)) {
        Remove-Item $tempClone -Recurse -Force -ErrorAction SilentlyContinue
    }
}
