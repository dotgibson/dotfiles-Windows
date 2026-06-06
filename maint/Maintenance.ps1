# ============================================================================
#  maint/Maintenance.ps1  -  the daily "update everything (that's safe)" runner.
# ============================================================================
#  Windows port of Core's maint/dotfiles-maint.sh. Invoked by Task Scheduler
#  (install it with `maint-install` from os/40-maint.ps1). Designed to run
#  UNATTENDED and NON-INTERACTIVE: every step is guarded and a failure of one
#  step never aborts the rest.
#
#  What it touches automatically (all USER-SPACE, low-risk):
#    • scoop:   update buckets, upgrade all apps, cleanup
#    • mise:    plugin update + upgrade   (if installed)
#    • neovim:  Lazy! sync / TSUpdate / MasonUpdate  (headless, timeout-guarded)
#    • PowerShell modules: PSReadLine / Terminal-Icons / PSFzf / CompletionPredictor
#
#  winget is OPT-IN: `winget upgrade --all` can launch MSI installers that prompt
#  or restart apps, which isn't safe to run blind. Enable it deliberately:
#    $env:MAINT_WINGET_UPGRADE = '1'   (set in the scheduled task or before a run)
#
#  Env knobs:
#    MAINT_ENABLED          1     # 0 = no-op
#    MAINT_WINGET_UPGRADE   0     # 1 = also `winget upgrade --all` (see above)
#    MAINT_NVIM_TIMEOUT     600   # seconds
# ============================================================================
[CmdletBinding()] param()

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\packages\modules.ps1')

# --- env knobs ----------------------------------------------------------------
if (-not $env:MAINT_ENABLED)        { $env:MAINT_ENABLED = '1' }
if (-not $env:MAINT_WINGET_UPGRADE) { $env:MAINT_WINGET_UPGRADE = '0' }
if (-not $env:MAINT_NVIM_TIMEOUT)   { $env:MAINT_NVIM_TIMEOUT = '600' }
if ($env:MAINT_ENABLED -ne '1') { return }

# --- paths / logging ----------------------------------------------------------
$LogDir = Join-Path $env:LOCALAPPDATA 'dotfiles\maint'
$Log    = Join-Path $LogDir 'maint.log'
$Lock   = Join-Path $LogDir '.lock'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log { param([string]$Msg) $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg; $line | Tee-Object -FilePath $Log -Append }
function Have { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# --- single-instance lock (mkdir-style: New-Item -ItemType Directory is atomic)
try {
    New-Item -ItemType Directory -Path $Lock -ErrorAction Stop | Out-Null
} catch {
    Write-Log "another run holds the lock ($Lock) — exiting"
    return
}
try {
    # --- log rotation (keep last ~600 lines) ----------------------------------
    if ((Test-Path $Log) -and ((Get-Content $Log -ErrorAction SilentlyContinue | Measure-Object).Count -gt 800)) {
        $tail = Get-Content $Log -Tail 600
        Set-Content -Path $Log -Value $tail
    }

    # --- labeled step that never aborts the script ----------------------------
    function Step {
        param([string]$Label, [scriptblock]$Body)
        Write-Log "> $Label"
        try { & $Body *>> $Log; Write-Log "  ok $Label" }
        catch { Write-Log "  FAIL $Label : $_  — continuing" }
    }

    # --- run a process with a timeout (for the headless nvim session) ---------
    function Invoke-WithTimeout {
        param([string]$File, [string[]]$ArgList, [int]$TimeoutSec)
        $p = Start-Process -FilePath $File -ArgumentList $ArgList -NoNewWindow -PassThru `
                -RedirectStandardOutput "$Log.nvim.out" -RedirectStandardError "$Log.nvim.err"
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            throw "timed out after ${TimeoutSec}s"
        }
        Get-Content "$Log.nvim.out","$Log.nvim.err" -ErrorAction SilentlyContinue | Add-Content $Log
        Remove-Item "$Log.nvim.out","$Log.nvim.err" -ErrorAction SilentlyContinue
    }

    Write-Log "=========== dotfiles-maint start ($([Environment]::MachineName)) ==========="

    # --- scoop ----------------------------------------------------------------
    if (Have scoop) {
        Step 'scoop update (buckets)' { scoop update }
        Step 'scoop upgrade (apps)'   { scoop update * }
        Step 'scoop cleanup'          { scoop cleanup *; scoop cache rm * }
    }

    # --- mise (runtime/tool versions) -----------------------------------------
    if (Have mise) {
        Step 'mise plugins update' { mise plugins update }
        Step 'mise upgrade'        { mise upgrade --yes }
    }

    # --- neovim: lazy.nvim sync + treesitter parsers + Mason registry ---------
    if (Have nvim) {
        Step 'neovim: Lazy sync / TSUpdate / MasonUpdate' {
            Invoke-WithTimeout -File (Get-Command nvim).Source `
                -ArgList @('--headless', '+Lazy! sync', '+silent! TSUpdateSync', '+silent! MasonUpdate', '+qa!') `
                -TimeoutSec ([int]$env:MAINT_NVIM_TIMEOUT)
        }
    }

    # --- navi cheatsheet repos -----------------------------------------------
    # `navi repo update` refreshes community cheatsheets. Silent - a network
    # blip here should never interrupt the rest of maintenance.
    if (Have navi) {
        Step 'navi repo update' { navi repo update }
    }

    # --- PowerShell modules ---------------------------------------------------
    foreach ($m in $script:MaintModuleNames) {
        if (Get-Module -ListAvailable $m) {
            Step "module update: $m" { Update-Module $m -Scope CurrentUser -Force -ErrorAction Stop }
        }
    }

    # --- winget (OPT-IN — see header) -----------------------------------------
    if ($env:MAINT_WINGET_UPGRADE -eq '1' -and (Have winget)) {
        Step 'winget upgrade --all' {
            winget upgrade --all --include-unknown --silent `
                --accept-package-agreements --accept-source-agreements
        }
    } else {
        Write-Log "winget upgrade SKIPPED (set MAINT_WINGET_UPGRADE=1 to enable; can launch MSI installers)"
    }

    Write-Log "=========== dotfiles-maint done ==========="
}
finally {
    Remove-Item $Lock -Recurse -Force -ErrorAction SilentlyContinue
}
