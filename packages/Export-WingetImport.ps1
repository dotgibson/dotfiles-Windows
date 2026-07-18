# ============================================================================
#  packages/Export-WingetImport.ps1  -  emit a real `winget import`-compatible
#  file from winget.json (this repo's own, dotfiles-native manifest).
#
#      .\packages\Export-WingetImport.ps1            # float to latest (ids only)
#      .\packages\Export-WingetImport.ps1 -Frozen    # pin versions from the lockfile
#      .\packages\Export-WingetImport.ps1 -DryRun    # print, write nothing
#
#  winget.json is this repo's own shape ({ packages: [ id | { id, group } ] }) so
#  the installer can carry optional-group tags winget itself doesn't understand —
#  which means it is NOT consumable by `winget import`. This generator projects it
#  down to the official export schema so a fresh box restores the whole set in one
#  command:
#      winget import -i packages/winget-import.json --accept-package-agreements `
#                    --accept-source-agreements
#
#  CreationDate / WinGetVersion (which `winget export` stamps) are deliberately
#  omitted so the output is DETERMINISTIC — regenerating on any box yields identical
#  bytes, so the committed artifact never shows spurious clock/version drift. Both
#  are optional for `winget import`.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$Frozen,
    [switch]$DryRun,
    # Where to write the import file. Defaults to packages/winget-import.json (the
    # committed artifact). Overridable so the drift test (tests/Packages.Tests.ps1)
    # can regenerate to a temp path and byte-compare without touching the repo copy.
    [string]$OutPath,
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

function Get-ExportWingetUsage {
    @(
        'Export-WingetImport.ps1 - project winget.json into a winget import file'
        ''
        'USAGE'
        '  .\packages\Export-WingetImport.ps1 [-Frozen] [-DryRun] [-Help]'
        ''
        'OPTIONS'
        '  -Frozen   Pin each package to its packages.lock.json version (default: float).'
        '  -DryRun   Print the resulting JSON and write nothing.'
        '  -Help     Show this help and exit.'
        ''
        'NOTES'
        '  Writes packages/winget-import.json. Restore a fresh box with:'
        '    winget import -i packages/winget-import.json --accept-package-agreements --accept-source-agreements'
    )
}

if ($Help) { Get-ExportWingetUsage | ForEach-Object { Write-Host $_ }; return }

# --- desired ids from the dotfiles-native manifest ---------------------------
# Entries are a bare id string OR { id, group }; normalize to id strings. The
# optional-group tag is intentionally dropped: an import file is the full declarative
# set (the installer's opt-out default installs everything anyway).
$wingetManifest = Get-Content (Join-Path $here 'winget.json') -Raw | ConvertFrom-Json
$ids = @($wingetManifest.packages |
        ForEach-Object { if ($_ -is [string]) { $_ } else { "$($_.id)" } } |
        Where-Object { $_ })

# --- optional version pins (-Frozen) -----------------------------------------
$lockMap = @{}
if ($Frozen) {
    $lockPath = Join-Path $here 'packages.lock.json'
    if (Test-Path $lockPath) {
        $lockMap = (Read-PackageLock (Get-Content $lockPath -Raw)).Winget
    } else {
        Write-DotWarn 'packages.lock.json not found - emitting unpinned ids.' 'generate the lock first, or drop -Frozen.'
    }
}

# --- assemble the official export schema -------------------------------------
$packages = foreach ($id in $ids) {
    $entry = [ordered]@{ PackageIdentifier = $id }
    $v = Get-LockedVersion -Map $lockMap -Name $id
    # Only pin a clean, exact version — never a range like "> 8.1" (winget import
    # treats Version as an exact match, so a range would resolve to nothing).
    if ($v -and $v -notmatch '[<>= ]') { $entry['Version'] = $v }
    [pscustomobject]$entry
}

$doc = [ordered]@{
    '$schema' = 'https://aka.ms/winget-packages.schema.2.0.json'
    Sources   = @(
        [ordered]@{
            Packages      = @($packages)
            SourceDetails = [ordered]@{
                Argument   = 'https://cdn.winget.microsoft.com/cache'
                Identifier = 'Microsoft.Winget.Source_8wekyb3d8bbwe'
                Name       = 'winget'
                Type       = 'Microsoft.PreIndexed.Package'
            }
        }
    )
}

$json = $doc | ConvertTo-Json -Depth 6

if ($DryRun) {
    Write-DotHost '--- winget-import.json (dry run) ---' -Color Cyan
    Write-Host $json
    return
}

$outPath = if ($OutPath) { $OutPath } else { Join-Path $here 'winget-import.json' }
# LF + UTF-8 (no BOM) + single trailing newline regardless of host OS — the same
# byte-clean write Update-PackageLock.ps1 uses so the repo's .editorconfig LF gate
# (which reads CRLF as trailing whitespace) stays green everywhere.
$json = ($json -replace "`r`n", "`n").TrimEnd("`n") + "`n"
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))
$pinNote = if ($Frozen) { ', pinned' } else { '' }
Write-DotOk "Wrote $outPath  ($($ids.Count) package(s)$pinNote)"
