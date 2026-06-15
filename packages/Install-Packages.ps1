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

# Shared rendering helpers (Write-DotWarn / Write-DotHost / glyphs). Dot-sourced
# so a standalone run gets the same NO_COLOR-aware layout as install.ps1; no-op
# if the file is missing (older checkout).
$lib = Join-Path $here '..\powershell\core\05-lib.ps1'
if (Test-Path $lib) { . $lib }

# Tiny progress line: "  [n/total] -> name" so a long, silent install doesn't look
# frozen. Returns a stopwatch the caller stops to print the elapsed time.
function Write-PkgStep {
    param([int]$N, [int]$Total, [string]$Name)
    Write-Host ("  [{0}/{1}] " -f $N, $Total) -ForegroundColor Cyan -NoNewline
    Write-Host "-> $Name" -ForegroundColor DarkGray
    [System.Diagnostics.Stopwatch]::StartNew()
}

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

# Wrap the whole batch so a Ctrl-C mid-install still prints the skipped/failed
# summary (U2) instead of vanishing — you can see exactly how far it got.
$script:PkgCompleted = $false
try {

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
    $apps = @($manifest.apps)
    $i = 0
    foreach ($app in $apps) {
        $i++
        $name = $app.Name
        if ($installed -contains $name) {
            Write-Host "  [$i/$($apps.Count)] = $name (already installed)" -ForegroundColor DarkGray
            continue
        }
        $sw = Write-PkgStep -N $i -Total $apps.Count -Name $name
        scoop install $name
        $sw.Stop()
        if ($LASTEXITCODE -ne 0) { $failed.Add("scoop:$name") }
        else { Write-DotHost ("      done in {0:n0}s" -f $sw.Elapsed.TotalSeconds) -Color DarkGray }
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
            Write-DotWarn 'winget export unavailable — falling back to per-package checks (slower).'
        }

        $pkgs = @($wg.packages)
        $j = 0
        foreach ($id in $pkgs) {
            $j++
            # Already installed? Prefer the exported set (-contains is
            # case-insensitive); fall back to a per-id query when export failed.
            $already = if ($exportOk) {
                $installedIds -contains $id
            } else {
                winget list --id $id -e --accept-source-agreements *> $null
                $LASTEXITCODE -eq 0
            }
            if ($already) {
                Write-Host "  [$j/$($pkgs.Count)] = $id (already installed)" -ForegroundColor DarkGray
                continue
            }
            $sw = Write-PkgStep -N $j -Total $pkgs.Count -Name $id
            winget install --id $id -e --silent `
                --accept-package-agreements --accept-source-agreements
            $sw.Stop()
            if ($LASTEXITCODE -ne 0) {
                Write-DotWarn "$id failed (winget exit $LASTEXITCODE) — skipping, continuing the batch"
                $failed.Add("winget:$id")
            } else {
                Write-DotHost ("      done in {0:n0}s" -f $sw.Elapsed.TotalSeconds) -Color DarkGray
            }
        }
    } else {
        Write-DotWarn 'winget not found.' 'Install "App Installer" from the Microsoft Store, then re-run with -SkipScoop.'
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
$mods = @($script:MaintModuleNames)
$k = 0
foreach ($m in $mods) {
    $k++
    if (Test-Path (Join-Path $localModules $m)) {
        Write-Host "  [$k/$($mods.Count)] = $m (already local)" -ForegroundColor DarkGray
        continue
    }
    $sw = Write-PkgStep -N $k -Total $mods.Count -Name $m
    try { Save-Module -Name $m -Path $localModules -Force -ErrorAction Stop; $sw.Stop() }
    catch { $sw.Stop(); Write-DotWarn "module $m failed: $_"; $failed.Add("module:$m") }
}

$script:PkgCompleted = $true

} finally {
    # --- summary (prints on completion AND on Ctrl-C) -------------------------
    Write-Host ''
    if (-not $script:PkgCompleted) {
        Write-DotWarn 'Package install interrupted — partial state below.' 'Re-run to resume (already-installed items are skipped).'
    }
    if ($failed.Count -eq 0 -and $script:PkgCompleted) {
        Write-DotHost 'Package install complete - no failures.' -Color Green
    } elseif ($failed.Count) {
        Write-DotHost "$($failed.Count) item(s) skipped:" -Color Yellow
        $failed | ForEach-Object { Write-DotHost "  - $_" -Color Yellow }
        Write-DotHost 'Re-run this script to retry them (already-installed apps are skipped).' -Color Yellow
    }
}
