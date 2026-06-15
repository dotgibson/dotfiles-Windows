# ============================================================================
#  uninstall.ps1  -  reverse install.ps1: remove the symlinks this repo created
#  and (optionally) restore the most recent backup install.ps1 set aside.
#
#  Usage (from the repo root):
#      .\uninstall.ps1                  # remove repo symlinks (prompts per item)
#      .\uninstall.ps1 -DryRun          # preview, remove nothing
#      .\uninstall.ps1 -RestoreBackups  # also restore newest *.bak for each link
#      .\uninstall.ps1 -Yes             # don't prompt
#      .\uninstall.ps1 -Help
#
#  Conservative on purpose: it ONLY removes links that actually point back into
#  this repo, so a user file or an unrelated config is never touched. Seeded
#  copies (~/.wslconfig, ~/.gitconfig.local, powershell/local.ps1) are left
#  alone — they're your data, not ours to delete.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RestoreBackups,
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$LibPath = Join-Path $RepoRoot 'powershell\core\05-lib.ps1'
if (Test-Path $LibPath) { . $LibPath }

# --- the set of links install.ps1 creates (pure: testable with injected env) ---
function Get-DotfilesLinkMap {
    param(
        [string]$HomeDir      = $HOME,
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$Documents    = [Environment]::GetFolderPath('MyDocuments')
    )
    # Defensive: a host with no resolvable Documents (or LOCALAPPDATA) must not
    # crash the map — fall back under HOME so the rest of the links still resolve.
    if (-not $Documents)    { $Documents    = Join-Path $HomeDir 'Documents' }
    if (-not $LocalAppData) { $LocalAppData = Join-Path $HomeDir 'AppData\Local' }
    @(
        (Join-Path $Documents    'PowerShell\Microsoft.PowerShell_profile.ps1')
        (Join-Path $LocalAppData 'nvim')
        (Join-Path $HomeDir      '.gitconfig')
        (Join-Path $HomeDir      '.gitignore_global')
        (Join-Path $HomeDir      '.ssh\config')
        (Join-Path $HomeDir      '.config\psmux\psmux.conf')
        (Join-Path $HomeDir      '.config\psmux\psmux.reset.conf')
        (Join-Path $HomeDir      '.config\psmux\scripts')
        (Join-Path $LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
    )
}

# True when $Link is a symlink whose target resolves inside this repo. Pure-ish
# (filesystem read only), shared shape with install.ps1's Test-SymlinkCurrent.
function Test-LinkIntoRepo {
    param([string]$Link, [string]$Root)
    if (-not (Test-Path -LiteralPath $Link)) { return $false }
    $item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.LinkType -ne 'SymbolicLink') { return $false }
    $target = @($item.Target)[0]
    return ($target -and $Root -and ($target -like "*$Root*"))
}

function Get-UninstallUsage {
    @(
        'uninstall.ps1 - remove the symlinks install.ps1 created'
        ''
        'USAGE'
        '  .\uninstall.ps1 [-DryRun] [-RestoreBackups] [-Yes] [-Help]'
        ''
        'OPTIONS'
        '  -DryRun           Preview what would be removed; change nothing.'
        '  -RestoreBackups   Restore the newest *.bak for each removed link.'
        '  -Yes              Remove without prompting.'
        '  -Help             Show this help and exit.'
    )
}

if ($Help) { Get-UninstallUsage | ForEach-Object { Write-Host $_ }; return }

# Library-only hook for the test suite.
if ($env:DOTFILES_UNINSTALL_LIBONLY -eq '1') { return }

if ($DryRun) {
    Write-Host ''
    Write-DotHost ' DRY RUN ' -Color Cyan
    Write-DotHost ' nothing will be removed or restored.' -Color DarkGray
}

$removed = 0; $restored = 0; $skipped = 0
Write-Host ''
Write-DotHost 'Removing dotfiles-Windows symlinks...' -Color Cyan

foreach ($link in Get-DotfilesLinkMap) {
    if (-not (Test-LinkIntoRepo -Link $link -Root $RepoRoot)) {
        # Not ours (missing, real file, or links elsewhere) — never touch it.
        continue
    }

    if ($DryRun) {
        Write-DotHost "  would remove  $link" -Color Cyan
        if ($RestoreBackups) { Write-DotHost "    and restore newest backup if present" -Color DarkGray }
        continue
    }

    if (-not ($Yes)) {
        try { $ans = Read-Host "  remove '$link'? [Y/n]" } catch { $ans = 'y' }
        if (-not ($ans -eq '' -or $ans -match '^(y|yes)$')) {
            Write-DotHost "  kept    $link" -Color DarkGray
            $skipped++
            continue
        }
    }

    Remove-Item -LiteralPath $link -Force -Recurse -ErrorAction SilentlyContinue
    Write-DotHost "  removed $link" -Color Green
    $removed++

    if ($RestoreBackups) {
        $bak = Get-ChildItem -Path (Split-Path -Parent $link) -Filter ((Split-Path -Leaf $link) + '.*.bak') `
                -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($bak) {
            Move-Item -LiteralPath $bak.FullName -Destination $link -Force
            Write-DotHost "  restored $link  (from $($bak.Name))" -Color Green
            $restored++
        }
    }
}

Write-Host ''
Write-DotHost ("Done: {0} removed, {1} restored, {2} kept." -f $removed, $restored, $skipped) -Color Green
if (-not $DryRun) {
    Write-Host 'Note: DOTFILES_WIN, ~/.wslconfig, ~/.gitconfig.local and powershell/local.ps1 were left as-is.' -ForegroundColor DarkGray
}
