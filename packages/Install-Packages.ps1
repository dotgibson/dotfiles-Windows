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
    [switch]$SkipScoop,
    [switch]$Help
)

# Pure usage banner (returns the lines, so -Help and the test agree — same shape
# as install.ps1's Get-InstallUsage).
function Get-PackagesUsage {
    @(
        'Install-Packages.ps1 - install the host toolchain from the manifests'
        ''
        'USAGE'
        '  .\packages\Install-Packages.ps1 [-SkipScoop] [-SkipWinget] [-Help]'
        ''
        'OPTIONS'
        '  -SkipScoop    Skip the scoop bucket/app install pass.'
        '  -SkipWinget   Skip the winget package install pass.'
        '  -Help         Show this help and exit.'
        ''
        'NOTES'
        '  Resilient: a package that fails is logged and skipped, never halting the'
        '  batch. Re-run to retry — already-installed items are detected and skipped.'
        '  PowerShell modules always install to a local (off-OneDrive) modules dir.'
    )
}

if ($Help) { Get-PackagesUsage | ForEach-Object { Write-Host $_ }; return }

$ErrorActionPreference = 'Continue'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$failed = [System.Collections.Generic.List[string]]::new()
. (Join-Path $here 'modules.ps1')

# Shared rendering helpers (Write-DotWarn / Write-DotHost / glyphs). Dot-sourced
# so a standalone run gets the same NO_COLOR-aware layout as install.ps1.
$lib = Join-Path $here '../powershell/core/05-lib.ps1'
if (Test-Path $lib) { . $lib }

# Make "best-effort if the lib is missing" actually true: if 05-lib didn't load
# (older/partial checkout), define minimal shims for the helpers this script uses
# so it degrades to plain output instead of erroring on an undefined command.
if (-not (Get-Command Write-DotHost -ErrorAction SilentlyContinue)) {
    function Write-DotHost { param([Parameter(Position = 0)][string]$Text = '', [string]$Color, [switch]$NoNewline) Write-Host $Text -NoNewline:$NoNewline }
    function Write-DotWarn { param([Parameter(Mandatory)][string]$Message, [string]$Hint) Write-Warning $Message; if ($Hint) { Write-Warning "  $Hint" } }
}

# Tiny progress line: "  [n/total] -> name" so a long, silent install doesn't look
# frozen. Returns a stopwatch the caller stops to print the elapsed time. Uses
# Write-DotHost so the progress line honours NO_COLOR like the rest of the output.
function Write-PkgStep {
    param([int]$N, [int]$Total, [string]$Name)
    Write-DotHost ("  [{0}/{1}] " -f $N, $Total) -Color Cyan -NoNewline
    Write-DotHost "-> $Name" -Color DarkGray
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

# --- optional version pinning (pure, unit-tested) -----------------------------
# Reproducibility without freezing the whole rolling toolchain: any manifest entry
# MAY pin a version, and the rest float to latest. A scoop app object can carry a
# Version ("Name@Version"); a winget entry can be either a bare id string or an
# object { "id": "...", "version": "..." }. These two helpers turn a manifest entry
# into the exact install token/spec, so the pinning logic is testable offline.
function Get-ScoopInstallToken {
    param($App)
    if ($App.Version) { "$($App.Name)@$($App.Version)" } else { "$($App.Name)" }
}
function ConvertTo-DotWingetSpec {
    param($Entry)
    if ($Entry -is [string]) { return [pscustomobject]@{ Id = $Entry; Version = $null } }
    return [pscustomobject]@{ Id = "$($Entry.id)"; Version = $(if ($Entry.version) { "$($Entry.version)" } else { $null }) }
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
            # Fetch the installer to a string first so it can be integrity-checked
            # before it runs, instead of piping the network straight into iex. Set
            # DOTFILES_SCOOP_SHA256 to the expected hash to gate execution; without
            # it we proceed (documented), but the seam for verification now exists.
            $scoopInstaller = Invoke-RestMethod 'https://get.scoop.sh'
            if ($env:DOTFILES_SCOOP_SHA256) {
                $actual = Get-DotStringSha256 $scoopInstaller
                if ($actual -ne ($env:DOTFILES_SCOOP_SHA256.ToLowerInvariant())) {
                    Write-DotErr 'scoop installer hash mismatch — refusing to run it.' "expected $($env:DOTFILES_SCOOP_SHA256), got $actual"
                    return
                }
                Write-DotOk 'scoop installer hash verified.'
            }
            $scoopInstaller | Invoke-Expression
        } catch {
            Write-DotErr "scoop bootstrap failed: $_"
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
        $token = Get-ScoopInstallToken $app   # Name, or Name@Version when pinned
        $sw = Write-PkgStep -N $i -Total $apps.Count -Name $token
        scoop install $token
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
            # winget export is silent and slow on a cold source — spin while it runs
            # (it writes $tmp on disk, so we still read the result back here). The job
            # returns winget's exit code so the original "export ok?" gate is intact.
            $rc = @(Invoke-DotSpinner -Label 'querying installed winget packages' -ArgumentList @($tmp) -Script {
                param($out)
                winget export -o $out --accept-source-agreements *> $null
                $LASTEXITCODE
            })[-1]
            if ($rc -eq 0 -and (Test-Path $tmp)) {
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
        foreach ($entry in $pkgs) {
            $j++
            $spec = ConvertTo-DotWingetSpec $entry   # { Id; Version (optional) }
            $id = $spec.Id
            $label = if ($spec.Version) { "$id @$($spec.Version)" } else { $id }
            # Already installed? Prefer the exported set (-contains is
            # case-insensitive); fall back to a per-id query when export failed.
            $already = if ($exportOk) {
                $installedIds -contains $id
            } else {
                winget list --id $id -e --accept-source-agreements *> $null
                $LASTEXITCODE -eq 0
            }
            if ($already) {
                Write-Host "  [$j/$($pkgs.Count)] = $label (already installed)" -ForegroundColor DarkGray
                continue
            }
            $sw = Write-PkgStep -N $j -Total $pkgs.Count -Name $label
            $wgInstall = @('install', '--id', $id, '-e', '--silent', '--accept-package-agreements', '--accept-source-agreements')
            if ($spec.Version) { $wgInstall += @('--version', $spec.Version) }
            winget @wgInstall
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
    # -RequiredVersion installs EXACTLY the pinned version (see packages/modules.ps1)
    # so a fresh bootstrap is reproducible; the daily maint runner rolls it forward.
    # Save-Module is silent and slow, so animate a spinner while it downloads (the
    # job returns 'ok' or 'fail: ...' so failure handling is preserved; inline on CI).
    $ver = $script:MaintModulePins[$m]
    $res = Invoke-DotSpinner -Label "downloading $m $ver" -ArgumentList @($m, $localModules, $ver) -Script {
        param($name, $path, $version)
        try { Save-Module -Name $name -Path $path -RequiredVersion $version -Force -ErrorAction Stop; 'ok' }
        catch { "fail: $_" }
    }
    $sw.Stop()
    $status = @($res)[-1]
    if ($status -eq 'ok') {
        Write-DotHost ("      done in {0:n0}s" -f $sw.Elapsed.TotalSeconds) -Color DarkGray
    } else {
        Write-DotWarn "module $m failed: $($status -replace '^fail:\s*', '')"; $failed.Add("module:$m")
    }
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
