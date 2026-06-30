# ============================================================================
#  tests/Assert-NvimParity.ps1  -  CI gate: nvim/ must match Core (B1)
#
#  nvim/ is the one tree this standalone repo vendors from dotfiles-core (see
#  nvim-sync.ps1). The sync stamps nvim/.core-ref with the Core commit it copied
#  from. This gate clones Core at THAT commit and diffs it against the vendored
#  nvim/, failing if they diverge — so a hand-edit straight into nvim/ (instead of
#  editing Core and re-syncing) can't silently fork the vendored tree.
#
#  It diffs against the RECORDED commit, not Core's current HEAD: the vendored
#  tree is expected to lag Core, so the invariant is "faithful copy of what we
#  synced", not "up to date with Core". Skips cleanly when .core-ref is absent or
#  has no resolved commit (e.g. a fresh checkout that hasn't run nvim-sync yet).
#
#  .core-ref (written only into the vendored copy) is excluded from the comparison.
#  lazy-lock.json is NOT excluded: it's synced from Core (cross-platform plugin
#  pins, see nvim-sync.ps1) and so must match the recorded Core commit like the
#  rest of the tree — the gate is what keeps the Windows pin from drifting.
#
#  Pure helpers are exposed for unit tests via DOTFILES_NVIMPARITY_LIBONLY=1.
# ============================================================================
[CmdletBinding()]
param([string]$CoreRemoteFallback = 'https://github.com/Gerrrt/dotfiles-core.git')

$DefaultExclude = @('.core-ref')

# --- Get-CoreRefField ---------------------------------------------------------
# Pull one `key = value` field out of .core-ref's lines; $null when absent.
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
    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    foreach ($f in Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force) {
        if ($Exclude -contains $f.Name) { continue }
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
        $map[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    $map
}

# --- Get-NvimParityDiff -------------------------------------------------------
# Compare the vendored tree's hash map against Core's: Missing = present in Core
# but not vendored, Extra = vendored but not in Core, Changed = same path, content
# differs. Pure.
function Get-NvimParityDiff {
    param([hashtable]$Local, [hashtable]$Core)
    $l = if ($Local) { $Local } else { @{} }
    $c = if ($Core) { $Core } else { @{} }
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
# True only for a hex git SHA (7-40 chars). Gates the UNTRUSTED .core-ref commit
# before it reaches git, so a malformed/option-like value can't be misread.
function Test-DotGitSha {
    param([string]$Value)
    [bool]($Value -match '^[0-9a-fA-F]{7,40}$')
}

# --- Resolve-CoreRemote -------------------------------------------------------
# Pick the clone remote: the .core-ref source ONLY when it's an allowlisted Core
# remote, else the canonical fallback. Keeps CI's outbound target out of
# PR-editable content's control.
function Resolve-CoreRemote {
    param([string]$Source, [string[]]$Allowed, [string]$Fallback)
    if ($Source -and ($Allowed -contains $Source)) { return $Source }
    $Fallback
}

# Library-only hook: let the test suite import the pure helpers without cloning.
if ($env:DOTFILES_NVIMPARITY_LIBONLY -eq '1') { return }

# --- main --------------------------------------------------------------------
$RepoRoot = Split-Path -Parent $PSScriptRoot
$nvim = Join-Path $RepoRoot 'nvim'
$refFile = Join-Path $nvim '.core-ref'

if (-not (Test-Path $refFile)) {
    Write-Host 'nvim parity: no nvim/.core-ref — skipped (run nvim-sync.ps1 to stamp provenance).'
    exit 0
}
$refLines = Get-Content $refFile
$commit = Get-CoreRefField $refLines 'commit'
$source = Get-CoreRefField $refLines 'source'
if (-not $commit -or $commit -eq 'unknown') {
    Write-Host 'nvim parity: .core-ref has no resolved commit — skipped.'
    exit 0
}
# .core-ref is tracked and PR-editable, so treat its fields as UNTRUSTED input to
# git/network:
#   • the commit must look like a real SHA — otherwise a malformed value (or one
#     starting with '-') could be taken by git as an option/refspec. This is a HARD
#     fail (exit 2), distinct from the intentional "unknown => skip" above.
#   • the clone target is restricted to an allowlist of known Core remotes; anything
#     else falls back to the canonical remote, so a hostile PR can't point CI's
#     outbound clone at an attacker-controlled URL.
if (-not (Test-DotGitSha $commit)) {
    Write-Error "nvim parity: .core-ref commit '$commit' is not a valid git SHA — refusing to use it."
    exit 2
}
$AllowedRemotes = @(
    'https://github.com/Gerrrt/dotfiles-core.git'
    'git@github.com:Gerrrt/dotfiles-core.git'
)
$remote = Resolve-CoreRemote -Source $source -Allowed $AllowedRemotes -Fallback $CoreRemoteFallback
if ($source -and ($AllowedRemotes -notcontains $source)) {
    Write-Host "  note: .core-ref source '$source' is not an allowlisted Core remote — using $CoreRemoteFallback."
}
Write-Host "nvim parity: checking nvim/ against $remote @ $commit"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('core-parity-' + [guid]::NewGuid().ToString('N'))
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
        if ($LASTEXITCODE -ne 0) { Write-Error "could not clone Core ($remote)"; exit 2 }
        git -C $tmp checkout --quiet $commit
        if ($LASTEXITCODE -ne 0) { Write-Error "Core has no commit $commit (force-pushed / gone?)"; exit 2 }
    }

    $coreNvim = Join-Path $tmp 'nvim'
    if (-not (Test-Path $coreNvim)) { Write-Error "Core @ $commit has no nvim/ tree"; exit 2 }

    $diff = Get-NvimParityDiff -Local (Get-NvimTreeHashes $nvim) -Core (Get-NvimTreeHashes $coreNvim)
    if ($diff.InSync) {
        Write-Host "nvim parity: OK — nvim/ matches Core @ $($commit.Substring(0,[Math]::Min(7,$commit.Length)))." -ForegroundColor Green
        exit 0
    }
    Write-Host 'nvim parity: DRIFT detected between nvim/ and the recorded Core commit.' -ForegroundColor Red
    foreach ($p in $diff.Changed) { Write-Host "  changed: nvim/$p" -ForegroundColor Yellow }
    foreach ($p in $diff.Extra) { Write-Host "  only in vendored nvim/: $p" -ForegroundColor Yellow }
    foreach ($p in $diff.Missing) { Write-Host "  missing from vendored nvim/ (in Core): $p" -ForegroundColor Yellow }
    Write-Host 'Fix by editing Core and re-running nvim-sync.ps1 (do not hand-edit nvim/).'
    exit 1
} finally {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}
