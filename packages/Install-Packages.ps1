# ============================================================================
#  Install-Packages.ps1  -  install the host toolchain from the manifests
#  Run from anywhere:  .\packages\Install-Packages.ps1
#
#  Resilient by design: a single package that fails (a flaky manifest, a
#  pre_install quirk like btop-lhm's, a transient download) is logged and
#  skipped - it never halts the whole batch. A summary prints at the end.
#
#  We force ErrorActionPreference = 'Continue' so that (a) scoop's own
#  pre/post-install scriptblocks, which run in THIS runspace, keep their normal
#  non-terminating behavior, and (b) we do NOT inherit a 'Stop' from install.ps1
#  when it calls us. Failures are tracked explicitly via $? and summarized.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$SkipWinget,
    [switch]$SkipScoop
)

$ErrorActionPreference = 'Continue'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$failed = [System.Collections.Generic.List[string]]::new()
. (Join-Path $here 'modules.ps1')

# --- Get-WingetInstalledIds ---------------------------------------------------
# Parse the PackageIdentifiers out of `winget export` JSON. Pulling the installed
# set ONCE this way replaces the old per-package `winget list --id` spawn (N
# subprocesses on a cold install). Pure, so it's unit-tested.
function Get-WingetInstalledIds {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    try { $obj = $Json | ConvertFrom-Json } catch { return @() }
    $ids = foreach ($s in $obj.Sources) { foreach ($p in $s.Packages) { $p.PackageIdentifier } }
    return @($ids | Where-Object { $_ })
}

# Library-only hook for the test suite: expose the helpers without installing.
if ($env:DOTFILES_PKG_LIBONLY -eq '1') { return }

# --- scoop --------------------------------------------------------------------
if (-not $SkipScoop) {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host 'Installing scoop...' -ForegroundColor Cyan
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Invoke-RestMethod get.scoop.sh | Invoke-Expression
        } catch {
            Write-Error "scoop bootstrap failed: $_"
            return
        }
    }

    $manifest = Get-Content (Join-Path $here 'scoopfile.json') -Raw | ConvertFrom-Json

    Write-Host 'Adding buckets...' -ForegroundColor Cyan
    $existing = (scoop bucket list).Name
    foreach ($b in $manifest.buckets) {
        if ($existing -notcontains $b.Name) {
            scoop bucket add $b.Name $b.Source
            if (-not $?) { $failed.Add("bucket:$($b.Name)") }
        }
    }

    Write-Host 'Installing scoop apps...' -ForegroundColor Cyan
    $installed = (scoop list 6>$null).Name
    foreach ($app in $manifest.apps) {
        $name = $app.Name
        if ($installed -contains $name) {
            Write-Host "  = $name (already installed)" -ForegroundColor DarkGray
            continue
        }
        Write-Host "  -> $name" -ForegroundColor DarkGray
        scoop install $name
        if ($LASTEXITCODE -ne 0) { $failed.Add("scoop:$name") }
    }
}

# --- winget -------------------------------------------------------------------
if (-not $SkipWinget) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host 'Installing winget packages...' -ForegroundColor Cyan
        $wg = Get-Content (Join-Path $here 'winget.json') -Raw | ConvertFrom-Json

        # Query the installed set ONCE via `winget export` (clean JSON) instead of
        # spawning `winget list --id` for every package — N fewer subprocesses.
        # If export fails (older winget, non-zero exit), fall back to the per-id
        # `winget list` check so we don't blindly reinstall everything.
        $installedIds = @()
        $exportOk = $false
        $tmp = $null
        try {
            $tmp = Join-Path $env:TEMP ("winget-export-" + [guid]::NewGuid().ToString('N') + '.json')
            winget export -o $tmp --accept-source-agreements *> $null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
                $installedIds = Get-WingetInstalledIds (Get-Content $tmp -Raw)
                $exportOk = $true
            }
        } catch { }
        finally { if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }
        if (-not $exportOk) {
            Write-Warning '  winget export unavailable - falling back to per-package checks (slower).'
        }

        foreach ($id in $wg.packages) {
            # Already installed? Prefer the exported set (-contains is
            # case-insensitive); fall back to a per-id query when export failed.
            $already = if ($exportOk) {
                $installedIds -contains $id
            } else {
                winget list --id $id -e --accept-source-agreements *> $null
                $LASTEXITCODE -eq 0
            }
            if ($already) {
                Write-Host "  = $id (already installed)" -ForegroundColor DarkGray
                continue
            }
            Write-Host "  -> $id" -ForegroundColor DarkGray
            winget install --id $id -e --silent `
                --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "  $id failed (winget exit $LASTEXITCODE) - skipping, continuing the batch"
                $failed.Add("winget:$id")
            }
        }
    } else {
        Write-Warning 'winget not found - install "App Installer" from the Microsoft Store, then re-run with -SkipScoop.'
    }
}

# --- PowerShell modules -------------------------------------------------------
# Save to a LOCAL (non-OneDrive) modules dir. Install-Module -Scope CurrentUser
# lands in Documents\PowerShell\Modules, which is OneDrive-synced when Documents
# is redirected — and importing from there adds seconds to every shell start.
# Save-Module writes the importable Name\Version layout to an explicit path;
# profile.ps1 prepends this dir to $env:PSModulePath so it's found first.
Write-Host 'Installing PowerShell modules (local, off OneDrive)...' -ForegroundColor Cyan
$localModules = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
New-Item -ItemType Directory -Force -Path $localModules | Out-Null
foreach ($m in $script:MaintModuleNames) {
    if (Test-Path (Join-Path $localModules $m)) {
        Write-Host "  = $m (already local)" -ForegroundColor DarkGray
        continue
    }
    Write-Host "  -> $m" -ForegroundColor DarkGray
    try { Save-Module -Name $m -Path $localModules -Force -ErrorAction Stop }
    catch { Write-Warning "  module $m failed: $_"; $failed.Add("module:$m") }
}

# --- summary ------------------------------------------------------------------
Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host 'Package install complete - no failures.' -ForegroundColor Green
} else {
    Write-Host "Package install complete, with $($failed.Count) item(s) skipped:" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host 'Re-run this script to retry them (already-installed apps are skipped).' -ForegroundColor Yellow
}
