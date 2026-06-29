# ============================================================================
#  starship-sync.ps1  -  refresh starship/starship.toml from dotfiles-core
#
#  dotfiles-Windows is a STANDALONE repo (no core/ subtree). starship is the rare
#  Core asset the host CAN share verbatim: starship.toml is cross-shell by design,
#  and Core now carries `powershell_indicator` in [shell] so the single canonical
#  file renders under both zsh and PowerShell. This is the small, deliberate sync
#  that keeps starship/starship.toml in lockstep with Core — the sibling of
#  nvim-sync.ps1 (whose pattern this mirrors exactly).
#
#  Usage (from the repo root):
#    .\starship-sync.ps1                                  # shallow-clone the remote, copy the toml
#    .\starship-sync.ps1 -CoreLocal C:\src\dotfiles-core  # copy from an existing clone instead
#    .\starship-sync.ps1 -Branch dev                      # sync from a different Core branch
#    .\starship-sync.ps1 -Ref v2.1.0                       # pin an exact Core commit/tag (reproducible)
#
#  After it runs: review `git diff starship/`, then commit.
# ============================================================================
[CmdletBinding()]
param(
    [string]$CoreRemote = 'https://github.com/Gerrrt/dotfiles-core.git',
    [string]$Branch     = 'main',
    [string]$CoreLocal,
    # Pin an EXACT Core commit/tag for a reproducible re-vendor. Takes precedence
    # over -Branch; can't be combined with -CoreLocal (which copies a local working
    # tree as-is). Validated/resolved by Get-StarshipSyncRefPlan.
    [string]$Ref
)

# --- Get-StarshipSyncRefPlan --------------------------------------------------
# Pure: decide what to fetch from the remote — a pinned -Ref (commit/tag, the
# reproducible case) or the -Branch tip — and reject the illegal combinations up
# front. Returns { Mode = 'ref'|'branch'; Target; Label }. Unit-tested via the
# DOTFILES_STARSHIPSYNC_LIBONLY hook below. (Mirrors nvim-sync.ps1's resolver.)
function Get-StarshipSyncRefPlan {
    [OutputType([pscustomobject])]
    param([string]$Ref, [string]$Branch = 'main', [string]$CoreLocal)
    if ($Ref -and $Ref.StartsWith('-')) {
        throw "invalid -Ref '$Ref': a git ref cannot start with '-'."
    }
    if ($Ref -and $CoreLocal) {
        throw '-Ref re-vendors from the remote and cannot be combined with -CoreLocal. Check out the ref in your local clone and pass -CoreLocal alone, or drop -CoreLocal to fetch the pinned ref.'
    }
    if ($Ref) { return [pscustomobject]@{ Mode = 'ref'; Target = $Ref; Label = "pinned ref $Ref" } }
    return [pscustomobject]@{ Mode = 'branch'; Target = $Branch; Label = "branch $Branch" }
}

# Library-only hook for the test suite: expose the resolver without syncing.
if ($env:DOTFILES_STARSHIPSYNC_LIBONLY -eq '1') { return }

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetDir = Join-Path $RepoRoot 'starship'
$Target    = Join-Path $TargetDir 'starship.toml'
$plan      = Get-StarshipSyncRefPlan -Ref $Ref -Branch $Branch -CoreLocal $CoreLocal

$tempClone = $null
try {
    # --- resolve the source starship.toml ------------------------------------
    if ($CoreLocal) {
        $srcToml = Join-Path $CoreLocal 'starship/starship.toml'
        if (-not (Test-Path $srcToml)) { throw "no starship/starship.toml under -CoreLocal path: $CoreLocal" }
        Write-Host "Using local Core clone: $srcToml" -ForegroundColor Cyan
    } else {
        $tempClone = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-core-" + [guid]::NewGuid().ToString('N'))
        if ($plan.Mode -eq 'ref') {
            # Fetch an EXACT commit/tag shallowly: a --branch clone can't name an
            # arbitrary commit, so init + fetch the ref + detach onto it. GitHub
            # allows fetching a reachable SHA directly.
            Write-Host "Fetching $CoreRemote @ $($plan.Target) (pinned)..." -ForegroundColor Cyan
            git init -q $tempClone
            if ($LASTEXITCODE -ne 0) { throw "git init failed (exit $LASTEXITCODE)" }
            git -C $tempClone remote add origin $CoreRemote
            git -C $tempClone fetch --depth 1 origin $plan.Target
            if ($LASTEXITCODE -ne 0) { throw "git fetch '$($plan.Target)' failed (exit $LASTEXITCODE) - is that ref pushed to the remote?" }
            git -C $tempClone checkout -q --detach FETCH_HEAD
            if ($LASTEXITCODE -ne 0) { throw "git checkout FETCH_HEAD failed (exit $LASTEXITCODE)" }
        } else {
            Write-Host "Shallow-cloning $CoreRemote ($($plan.Target))..." -ForegroundColor Cyan
            git clone --depth 1 --branch $plan.Target $CoreRemote $tempClone
            if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
        }
        $srcToml = Join-Path $tempClone 'starship/starship.toml'
        if (-not (Test-Path $srcToml)) { throw "cloned Core has no starship/starship.toml" }
    }

    # --- copy source -> target ------------------------------------------------
    # A single file (unlike nvim's tree), so a plain copy — no robocopy /MIR. This
    # is the canonical, cross-shell starship.toml; we take it verbatim so the host
    # prompt matches the fleet.
    Write-Host 'Syncing starship/starship.toml ...' -ForegroundColor Cyan
    if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir | Out-Null }
    Copy-Item -Path $srcToml -Destination $Target -Force

    # --- record vendoring provenance -> starship/.core-ref --------------------
    # Stamp WHICH Core commit this toml came from, the moment we copy — same B1
    # marker nvim/.core-ref carries, so dotfiles-doctor / fleet-drift can tell a
    # current file from a stale one. Best-effort: a non-git -CoreLocal yields
    # 'unknown', still a truthful record.
    $srcRepo  = if ($CoreLocal) { $CoreLocal }  else { $tempClone }
    $srcLabel = if ($CoreLocal) { $CoreLocal }  else { $CoreRemote }
    $sha  = (& git -C $srcRepo rev-parse HEAD 2>$null)
    $when = (& git -C $srcRepo show -s --format=%cs HEAD 2>$null)
    $refFile = Join-Path $TargetDir '.core-ref'
    $now = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    @(
        '# dotfiles-Windows :: starship vendor provenance (written by starship-sync.ps1)'
        '# The Core commit this starship.toml was vendored from. dotfiles-doctor reads it.'
        "source = $srcLabel"
        "branch = $Branch"
        "pinned = $(if ($Ref) { $Ref } else { '(branch tip)' })"
        "commit = $(if ($sha)  { $sha }  else { 'unknown' })"
        "date   = $(if ($when) { $when } else { 'unknown' })"
        "synced = $now"
    ) | Set-Content -Path $refFile -Encoding UTF8
    $shortSha = if ($sha) { $sha.Substring(0, [Math]::Min(7, $sha.Length)) } else { 'unknown' }
    Write-Host "  recorded provenance -> starship/.core-ref (core@$shortSha)" -ForegroundColor DarkGray

    Write-Host ''
    Write-Host 'starship.toml synced from Core. Review and commit:' -ForegroundColor Green
    Write-Host "  git -C `"$RepoRoot`" diff starship/" -ForegroundColor DarkGray
    Write-Host "  git -C `"$RepoRoot`" add starship/ ; git -C `"$RepoRoot`" commit -m 'sync starship from core'" -ForegroundColor DarkGray
}
finally {
    if ($tempClone -and (Test-Path $tempClone)) {
        Remove-Item $tempClone -Recurse -Force -ErrorAction SilentlyContinue
    }
}
