# ============================================================================
#  windows/defaults.ps1  -  Windows preferences as code (the pwsh twin of the
#  sibling dotfiles-MacBook repo's macos/defaults.sh — NOT a file in this repo).
#
#      pwsh -File windows/defaults.ps1            # apply
#      pwsh -File windows/defaults.ps1 -DryRun    # print what would change, write nothing
#      pwsh -File windows/defaults.ps1 -Help
#
#  Every tweak is an HKCU (current-user) registry value — so this needs NO admin
#  and touches nothing machine-wide or for other users. Each write is idempotent
#  (safe to re-run). These are the handful of privacy/telemetry + Explorer tweaks
#  worth codifying instead of clicking through a debloat GUI (Wintoys / ShutUp10 /
#  winutil): here they're diffable, reviewable, and reproducible on a fresh box.
#
#  Read it before you run it — these are MY preferences; comment out anything you
#  disagree with. Explorer/taskbar changes need an Explorer restart (or sign-out)
#  to show; pass -RestartExplorer to bounce it at the end.
# ============================================================================
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RestartExplorer,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Shared rendering helpers (degrade to plain Write-Host if 05-lib is absent) — the
# same dot-source-or-fallback dance packages/Update-PackageLock.ps1 uses so this
# speaks the fleet's colours when run from a checkout.
$lib = Join-Path $here '../powershell/core/05-lib.ps1'
if (Test-Path $lib) { . $lib }
if (-not (Get-Command Write-DotHost -ErrorAction SilentlyContinue)) {
    function Write-DotHost { param([Parameter(Position = 0)][string]$Text = '', [string]$Color, [switch]$NoNewline) Write-Host $Text -NoNewline:$NoNewline }
    function Write-DotOk   { param([Parameter(Mandatory)][string]$Message) Write-Host $Message }
}

function Get-DefaultsUsage {
    @(
        'defaults.ps1 - apply Windows privacy/Explorer preferences (HKCU, no admin)'
        ''
        'USAGE'
        '  pwsh -File windows/defaults.ps1 [-DryRun] [-RestartExplorer] [-Help]'
        ''
        'OPTIONS'
        '  -DryRun            Print the intended changes and write nothing.'
        '  -RestartExplorer   Restart Explorer at the end so shell changes show now.'
        '  -Help              Show this help and exit.'
    )
}

if ($Help) { Get-DefaultsUsage | ForEach-Object { Write-Host $_ }; return }

$script:Applied = 0

# One helper so the tweak list below reads as data. In -DryRun it only prints;
# otherwise it creates the key path if missing, then sets the value (idempotent).
# Verb is "Apply" on purpose — not a state-changing approved verb, so PSScriptAnalyzer
# doesn't demand ShouldProcess plumbing on a personal setup script.
function Apply-DotReg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'String', 'ExpandString', 'QWord')][string]$Type = 'DWord',
        [Parameter(Mandatory)][string]$Because
    )
    $label = "$Because  ($Path\$Name = $Value)"
    if ($DryRun) { Write-DotHost "  would set  $label" -Color DarkGray; return }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-DotHost "  set  $label" -Color DarkGray
    $script:Applied++
}

Write-DotHost 'Windows preferences (HKCU, no admin)…' -Color Cyan
if ($DryRun) { Write-DotHost '  (dry run — nothing will be written)' -Color Yellow }

# --- privacy / telemetry ------------------------------------------------------
# Per-user advertising ID that personalizes ads across apps. Default: 1 (on).
Apply-DotReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 -Because 'disable advertising ID'
# Apps reading your language list to tailor content. Default: 0 (opted in).
Apply-DotReg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 -Because 'opt out of language-list tracking'
# Start-menu "suggestions" (promoted/sponsored apps). Default: 1 (on).
Apply-DotReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0 -Because 'no Start-menu app suggestions'
# "Tips, tricks and suggestions" notifications as you use Windows. Default: 1 (on).
Apply-DotReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0 -Because 'no Windows tips/notifications'
# Bing / web results in Start search — keep Start local. Default: 1 (on).
Apply-DotReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 -Because 'no Bing/web results in Start search'

# --- Explorer power-user defaults --------------------------------------------
# Show file extensions (HideFileExt = 0). Default: 1 (hidden — the phishing footgun).
Apply-DotReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0 -Because 'show file extensions'
# Open Explorer to "This PC" instead of Quick Access (LaunchTo = 1). Default: 2 (Quick Access).
Apply-DotReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1 -Because 'open Explorer to This PC'
# Taskbar search as an icon, not the wide box (SearchboxTaskbarMode = 1). Default: 2 (box).
Apply-DotReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1 -Because 'shrink taskbar search to an icon'

# --- summary ------------------------------------------------------------------
if ($DryRun) {
    Write-DotOk 'dry run complete — re-run without -DryRun to apply.'
} else {
    Write-DotOk "applied $script:Applied preference(s)."
    if ($RestartExplorer) {
        Write-DotHost '  restarting Explorer…' -Color DarkGray
        # Windows relaunches the shell process automatically when it's killed.
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    } else {
        Write-DotHost '  sign out (or re-run with -RestartExplorer) for the Explorer/taskbar changes to show.' -Color DarkGray
    }
}
