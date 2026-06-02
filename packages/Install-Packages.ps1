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
        if (-not $?) {
            Write-Warning "  $name reported errors - skipping it, continuing the batch"
            $failed.Add("scoop:$name")
        }
    }
}

# --- winget -------------------------------------------------------------------
if (-not $SkipWinget) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host 'Installing winget packages...' -ForegroundColor Cyan
        $wg = Get-Content (Join-Path $here 'winget.json') -Raw | ConvertFrom-Json
        foreach ($id in $wg.packages) {
            # already installed? `winget list` exits 0 when the id is present.
            winget list --id $id -e --accept-source-agreements *> $null
            if ($LASTEXITCODE -eq 0) {
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
Write-Host 'Installing PowerShell modules...' -ForegroundColor Cyan
foreach ($m in 'PSReadLine','Terminal-Icons','PSFzf','CompletionPredictor') {
    if (-not (Get-Module -ListAvailable $m)) {
        Write-Host "  -> $m" -ForegroundColor DarkGray
        try { Install-Module $m -Scope CurrentUser -Force -AllowClobber }
        catch { Write-Warning "  module $m failed: $_"; $failed.Add("module:$m") }
    }
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

