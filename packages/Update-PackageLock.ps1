# ============================================================================
#  packages/Update-PackageLock.ps1  -  regenerate packages.lock.json (B4)
#  Run on a working Windows box that already has the toolchain installed:
#      .\packages\Update-PackageLock.ps1
#      .\packages\Update-PackageLock.ps1 -DryRun   # print, write nothing
#
#  Captures the EXACT installed versions of the managed apps (the ones listed in
#  scoopfile.json / winget.json) into a resolved lockfile, so a later
#  `Install-Packages.ps1 -Frozen` reproduces this baseline. Apps you have
#  installed but don't manage are ignored; managed apps you DON'T have installed
#  are reported and left unlocked (you can't pin a version you've never resolved).
#
#  Commit the resulting packages.lock.json — it is the reproducibility anchor.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'PackageLock.ps1')

# Shared rendering helpers (degrade to plain Write-Host if 05-lib is absent).
$lib = Join-Path $here '../powershell/core/05-lib.ps1'
if (Test-Path $lib) { . $lib }
if (-not (Get-Command Write-DotHost -ErrorAction SilentlyContinue)) {
    function Write-DotHost { param([Parameter(Position = 0)][string]$Text = '', [string]$Color, [switch]$NoNewline) Write-Host $Text -NoNewline:$NoNewline }
    function Write-DotWarn { param([Parameter(Mandatory)][string]$Message, [string]$Hint) Write-Warning $Message; if ($Hint) { Write-Warning "  $Hint" } }
    function Write-DotOk   { param([Parameter(Mandatory)][string]$Message) Write-Host $Message }
}

function Get-UpdateLockUsage {
    @(
        'Update-PackageLock.ps1 - capture exact installed versions into packages.lock.json'
        ''
        'USAGE'
        '  .\packages\Update-PackageLock.ps1 [-DryRun] [-Help]'
        ''
        'OPTIONS'
        '  -DryRun   Print the resolved lock and write nothing.'
        '  -Help     Show this help and exit.'
        ''
        'NOTES'
        '  Run on a box that already has the managed toolchain installed. Only the'
        '  apps listed in scoopfile.json / winget.json are locked. Commit the result.'
    )
}

if ($Help) { Get-UpdateLockUsage | ForEach-Object { Write-Host $_ }; return }

# Managed (desired) names from the manifests.
$scoopManifest = Get-Content (Join-Path $here 'scoopfile.json') -Raw | ConvertFrom-Json
$wingetManifest = Get-Content (Join-Path $here 'winget.json')  -Raw | ConvertFrom-Json
$scoopNames = @($scoopManifest.apps | ForEach-Object { $_.Name })
$wingetIds = @($wingetManifest.packages | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } })

# --- resolve installed scoop versions ----------------------------------------
$scoopResolved = @{}
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-DotHost 'Querying installed scoop versions...' -Color Cyan
    # Capture + gate on the exit code: a non-zero `scoop export` (or non-JSON output)
    # must NOT pass for "nothing installed" — that would misreport every app as
    # missing and silently write an empty lock.
    $scoopRaw = (scoop export 6>$null) | Out-String
    if ($LASTEXITCODE -eq 0) {
        $scoopResolved = ConvertFrom-ScoopExport $scoopRaw
    } else {
        Write-DotWarn "scoop export failed (exit $LASTEXITCODE) - scoop apps left unlocked." 're-run once scoop is healthy.'
    }
} else {
    Write-DotWarn 'scoop not found - scoop apps will be left unlocked.'
}

# --- resolve installed winget versions ---------------------------------------
$wingetResolved = @{}
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-DotHost 'Querying installed winget versions...' -Color Cyan
    $tmp = Join-Path $env:TEMP ("winget-lock-" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        winget export -o $tmp --include-versions --accept-source-agreements *> $null
        # Only trust the temp file when winget actually succeeded — a non-zero exit
        # can still leave a stale/partial file from a previous run on disk.
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
            $wingetResolved = ConvertFrom-WingetExport (Get-Content $tmp -Raw)
        } else {
            Write-DotWarn "winget export failed (exit $LASTEXITCODE) - winget packages left unlocked." 're-run once winget is healthy.'
        }
    } catch {
        Write-DotWarn "winget export failed: $_" 'winget packages will be left unlocked.'
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
} else {
    Write-DotWarn 'winget not found - winget packages will be left unlocked.'
}

# --- restrict to the managed set; report anything unresolvable ---------------
function Select-Managed {
    param([string[]]$Names, [hashtable]$Resolved, [string]$Kind, [string[]]$Unpinnable)
    $out = @{}
    $skip = @($Unpinnable | Where-Object { $_ })
    $unresolved = [System.Collections.Generic.List[string]]::new()
    $expected = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $Names) {
        $v = Get-LockedVersion -Map $Resolved -Name $n
        if ($v) { $out[$n] = $v }
        elseif ($skip -contains $n) { $expected.Add($n) }
        else { $unresolved.Add($n) }
    }
    # Two different situations, two different messages: an unpinnable package is
    # working as designed (nothing to fix), a genuinely missing one is actionable.
    if ($expected.Count) {
        Write-DotHost "  ${Kind}: $($expected.Count) self-updating package(s) left unlocked by design: $($expected -join ', ')" -Color DarkGray
    }
    if ($unresolved.Count) {
        Write-DotWarn "${Kind}: $($unresolved.Count) managed app(s) not installed - left unlocked: $($unresolved -join ', ')" `
            'install them, then re-run to lock their versions.'
    }
    $out
}
$scoopLock  = Select-Managed -Names $scoopNames  -Resolved $scoopResolved  -Kind 'scoop'
$wingetLock = Select-Managed -Names $wingetIds   -Resolved $wingetResolved -Kind 'winget' -Unpinnable (Get-UnpinnableWingetId)

$lock = New-PackageLockObject -Scoop $scoopLock -Winget $wingetLock -GeneratedAt (Get-Date -Format 'o')
$json = $lock | ConvertTo-Json -Depth 5

if ($DryRun) {
    Write-DotHost '--- packages.lock.json (dry run) ---' -Color Cyan
    Write-Host $json
    return
}

$lockPath = Join-Path $here 'packages.lock.json'
# Write LF + UTF-8 (no BOM) + a single trailing newline, REGARDLESS of host OS:
# Set-Content on Windows emits CRLF, which trips the repo's LF .editorconfig gate
# (every line reads as trailing whitespace). WriteAllText bypasses PowerShell's
# platform newline translation so the committed lock is byte-clean everywhere.
$json = ($json -replace "`r`n", "`n").TrimEnd("`n") + "`n"
[System.IO.File]::WriteAllText($lockPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-DotOk "Wrote $lockPath  (scoop: $($scoopLock.Count), winget: $($wingetLock.Count))"
