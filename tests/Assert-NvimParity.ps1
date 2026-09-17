# ============================================================================
#  tests/Assert-NvimParity.ps1  -  CI gate: nvim/ must match its recorded pin
#
#  nvim/ is the one tree this standalone repo vendors, and since
#  dotfiles-core#1124 it is vendored from dotgibson/dotfiles-nvim directly rather
#  than out of dotfiles-core (see nvim-sync.ps1). The sync stamps nvim.lock with
#  the upstream commit it copied from. This gate clones that repo at THAT commit
#  and diffs it against the vendored nvim/, failing if they diverge — so a
#  hand-edit straight into nvim/ (instead of editing upstream and re-syncing)
#  can't silently fork the vendored tree.
#
#  It diffs against the RECORDED commit, not upstream's current HEAD: the vendored
#  tree is expected to lag a release line, so the invariant is "faithful copy of
#  what we pinned", not "up to date with upstream". Skips cleanly when nvim.lock is
#  absent or has no resolved commit (e.g. a fresh checkout that hasn't run
#  nvim-sync yet).
#
#  NOTHING IS EXCLUDED FROM THE COMPARISON, and that is new. The provenance marker
#  used to live at nvim/.core-ref — inside the very tree being compared — so it had
#  to be excluded by name. Moving the pin out to the repo root (dotfiles-core#1124)
#  means the vendored nvim/ is now byte-identical to upstream's, and the gate needs
#  no exclusion set to say so. lazy-lock.json is compared like everything else:
#  it's vendored too (cross-platform plugin pins, see nvim-sync.ps1), and the gate
#  is what keeps the Windows copy from drifting off the pinned plugin set.
#
#  Pure helpers are exposed for unit tests via DOTFILES_NVIMPARITY_LIBONLY=1.
# ============================================================================
[CmdletBinding()]
param([string]$NvimRepoFallback = 'dotgibson/dotfiles-nvim')

# Empty on purpose — see the header. Kept as a parameterized default rather than
# deleted so the helper stays unit-testable against a non-empty set.
$DefaultExclude = @()

# --- Get-CoreRefField ---------------------------------------------------------
# Pull one field out of a provenance marker's lines; $null when absent. Tolerates
# both `key=value` (nvim.lock's spelling, mirroring dotfiles-core's own) and
# `key = value` (the .core-ref spelling starship/ and theme/ still use), so ONE
# reader serves all three markers.
#
# The name is about the marker FORMAT, not about dotfiles-core: Assert-Starship-
# Parity.ps1 and Assert-ThemeParity.ps1 dot-source this file for exactly this
# function (plus Test-DotGitSha and Resolve-CoreRemote), deliberately, so the
# untrusted-input guards have one copy. Renaming it forks that contract for
# nothing.
function Get-CoreRefField {
    param([string[]]$Lines, [string]$Key)
    $line = $Lines | Where-Object { $_ -match "^\s*$([regex]::Escape($Key))\s*=" } | Select-Object -First 1
    if (-not $line) { return $null }
    ($line -replace "^\s*$([regex]::Escape($Key))\s*=\s*", '').Trim()
}

# --- Get-NvimTreeHashes -------------------------------------------------------
# Map of <relative posix path> -> SHA256 for every file under $Root, skipping the
# excluded leaf names. The relative, separator-normalized keys make the two trees
# comparable regardless of OS or absolute location.
function Get-NvimTreeHashes {
    param([string]$Root, [string[]]$Exclude = $DefaultExclude)
    $map = @{}
    if (-not (Test-Path $Root)) { return $map }
    # .ProviderPath, not .Path: for a UNC root the latter comes back carrying the
    # `Microsoft.PowerShell.Core\FileSystem::` provider prefix, which is LONGER than
    # the FullName it is about to be subtracted from — the Substring below then
    # throws instead of comparing. Drive-letter roots are unaffected, which is why
    # CI never saw it; running the gate from a \\wsl.localhost checkout does.
    $rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')
    foreach ($f in Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force) {
        if ($Exclude -contains $f.Name) { continue }
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
        $map[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    $map
}

# --- Get-NvimParityDiff -------------------------------------------------------
# Compare the vendored tree's hash map against upstream's: Missing = present
# upstream but not vendored, Extra = vendored but not upstream, Changed = same
# path, content differs. Pure.
function Get-NvimParityDiff {
    param([hashtable]$Local, [hashtable]$Upstream)
    $l = if ($Local) { $Local } else { @{} }
    $c = if ($Upstream) { $Upstream } else { @{} }
    $missing = @($c.Keys | Where-Object { -not $l.ContainsKey($_) } | Sort-Object)
    $extra = @($l.Keys | Where-Object { -not $c.ContainsKey($_) } | Sort-Object)
    $changed = @($c.Keys | Where-Object { $l.ContainsKey($_) -and $l[$_] -ne $c[$_] } | Sort-Object)
    [pscustomobject]@{
        Missing = $missing
        Extra   = $extra
        Changed = $changed
        InSync  = ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $changed.Count -eq 0)
    }
}

# --- Test-DotGitSha -----------------------------------------------------------
# True only for a hex git SHA (7-40 chars). Gates the UNTRUSTED nvim.lock commit
# before it reaches git, so a malformed/option-like value can't be misread.
function Test-DotGitSha {
    param([string]$Value)
    [bool]($Value -match '^[0-9a-fA-F]{7,40}$')
}

# --- Resolve-CoreRemote -------------------------------------------------------
# Pick the clone remote: the marker's `source` URL ONLY when it's an allowlisted
# Core remote, else the canonical fallback. Keeps CI's outbound target out of
# PR-editable content's control.
#
# STILL URL-SHAPED, and still here, because starship/ and theme/ are still
# vendored from dotfiles-core and still record a `source` URL. The nvim gate no
# longer calls it — see Resolve-NvimRepo below.
function Resolve-CoreRemote {
    param([string]$Source, [string[]]$Allowed, [string]$Fallback)
    if ($Source -and ($Allowed -contains $Source)) { return $Source }
    $Fallback
}

# --- Resolve-NvimRepo ---------------------------------------------------------
# The nvim gate's own target resolver: nvim.lock's nvim_repo ONLY when it's an
# allowlisted `owner/name` slug, else the canonical fallback. Same guarantee as
# Resolve-CoreRemote, against a different shape of value.
#
# A SLUG, not a URL, and that is a small hardening win: the allowlist no longer
# has to enumerate every spelling of the same repo (https, ssh, with and without
# .git), and the URL CI actually dials is BUILT by the caller from a value that
# has already been matched against the allowlist — so a `source`-style field can
# no longer smuggle a host through by dressing itself up as one of the accepted
# spellings.
function Resolve-NvimRepo {
    param([string]$Repo, [string[]]$Allowed, [string]$Fallback)
    if ($Repo -and ($Allowed -contains $Repo)) { return $Repo }
    $Fallback
}

# Library-only hook: let the test suite import the pure helpers without cloning.
if ($env:DOTFILES_NVIMPARITY_LIBONLY -eq '1') { return }

# --- main --------------------------------------------------------------------
$RepoRoot = Split-Path -Parent $PSScriptRoot
$nvim = Join-Path $RepoRoot 'nvim'
$lockFile = Join-Path $RepoRoot 'nvim.lock'

if (-not (Test-Path $lockFile)) {
    Write-Host 'nvim parity: no nvim.lock — skipped (run nvim-sync.ps1 to stamp provenance).'
    exit 0
}
$lockLines = Get-Content $lockFile
$commit = Get-CoreRefField $lockLines 'nvim_sha'
$repo = Get-CoreRefField $lockLines 'nvim_repo'
$tag = Get-CoreRefField $lockLines 'nvim_tag'
if (-not $commit -or $commit -eq 'unknown') {
    Write-Host 'nvim parity: nvim.lock has no resolved commit — skipped.'
    exit 0
}
# nvim.lock is tracked and PR-editable, so treat its fields as UNTRUSTED input to
# git/network:
#   • the commit must look like a real SHA — otherwise a malformed value (or one
#     starting with '-') could be taken by git as an option/refspec. This is a HARD
#     fail (exit 2), distinct from the intentional "unknown => skip" above.
#   • the clone target is restricted to an allowlist of known repos; anything else
#     falls back to the canonical one, so a hostile PR can't point CI's outbound
#     clone at an attacker-controlled URL.
if (-not (Test-DotGitSha $commit)) {
    Write-Error "nvim parity: nvim.lock nvim_sha '$commit' is not a valid git SHA — refusing to use it."
    exit 2
}
$AllowedRepos = @('dotgibson/dotfiles-nvim')
$slug = Resolve-NvimRepo -Repo $repo -Allowed $AllowedRepos -Fallback $NvimRepoFallback
if ($repo -and ($AllowedRepos -notcontains $repo)) {
    Write-Host "  note: nvim.lock nvim_repo '$repo' is not an allowlisted repo — using $NvimRepoFallback."
}
$remote = "https://github.com/$slug.git"
Write-Host "nvim parity: checking nvim/ against $slug @ $commit$(if ($tag) { " ($tag)" })"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('nvim-parity-' + [guid]::NewGuid().ToString('N'))
try {
    # Fetch exactly the recorded commit (GitHub allows fetch-by-SHA). Fall back to a
    # full clone + checkout if the server refuses a bare-SHA fetch.
    git init --quiet $tmp
    git -C $tmp remote add origin $remote
    git -C $tmp fetch --depth 1 --quiet origin $commit 2>$null
    git -C $tmp checkout --quiet FETCH_HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  bare-SHA fetch unavailable — falling back to a full clone.'
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        git clone --quiet $remote $tmp
        if ($LASTEXITCODE -ne 0) { Write-Error "could not clone $slug ($remote)"; exit 2 }
        git -C $tmp checkout --quiet $commit
        if ($LASTEXITCODE -ne 0) { Write-Error "$slug has no commit $commit (force-pushed / gone?)"; exit 2 }
    }

    # The payload is upstream's nvim/ SUBDIRECTORY: dotfiles-nvim carries its own
    # gate, CI and docs beside the editor tree, and only the tree is vendored here.
    $upstreamNvim = Join-Path $tmp 'nvim'
    if (-not (Test-Path $upstreamNvim)) { Write-Error "$slug @ $commit has no nvim/ tree"; exit 2 }

    $diff = Get-NvimParityDiff -Local (Get-NvimTreeHashes $nvim) -Upstream (Get-NvimTreeHashes $upstreamNvim)
    if ($diff.InSync) {
        Write-Host "nvim parity: OK — nvim/ matches $slug @ $($commit.Substring(0,[Math]::Min(7,$commit.Length)))." -ForegroundColor Green
        exit 0
    }
    Write-Host 'nvim parity: DRIFT detected between nvim/ and the commit nvim.lock records.' -ForegroundColor Red
    foreach ($p in $diff.Changed) { Write-Host "  changed: nvim/$p" -ForegroundColor Yellow }
    foreach ($p in $diff.Extra) { Write-Host "  only in vendored nvim/: $p" -ForegroundColor Yellow }
    foreach ($p in $diff.Missing) { Write-Host "  missing from vendored nvim/ (upstream has it): $p" -ForegroundColor Yellow }
    Write-Host "Fix by editing $slug and re-running nvim-sync.ps1 (do not hand-edit nvim/)."
    exit 1
} finally {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}
