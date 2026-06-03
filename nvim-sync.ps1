# ============================================================================
#  nvim-sync.ps1  -  refresh nvim/ from dotfiles-core (standalone; NO subtree)
#
#  dotfiles-Windows is a STANDALONE repo. It does not vendor Core as a subtree,
#  because PowerShell can't consume Core's zsh/tmux/bash layers — the only Core
#  asset worth sharing on the host is the Neovim Lua tree. This script is the
#  small, deliberate sync that keeps nvim/ in lockstep with Core, the way the
#  subtree does automatically on the Unix repos.
#
#  Usage (from the repo root):
#    .\nvim-sync.ps1                                  # shallow-clone the remote, copy nvim/
#    .\nvim-sync.ps1 -CoreLocal C:\src\dotfiles-core  # copy from an existing clone instead
#    .\nvim-sync.ps1 -Branch dev                      # sync from a different Core branch
#
#  After it runs: review `git diff nvim/`, then commit. lazy-lock.json is left
#  untouched (it's environment-specific and gitignored here).
# ============================================================================
[CmdletBinding()]
param(
    [string]$CoreRemote = 'https://github.com/Gerrrt/dotfiles-core.git',
    [string]$Branch     = 'main',
    [string]$CoreLocal
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target   = Join-Path $RepoRoot 'nvim'

$tempClone = $null
try {
    # --- resolve the source nvim tree ----------------------------------------
    if ($CoreLocal) {
        $srcNvim = Join-Path $CoreLocal 'nvim'
        if (-not (Test-Path $srcNvim)) { throw "no nvim/ under -CoreLocal path: $CoreLocal" }
        Write-Host "Using local Core clone: $srcNvim" -ForegroundColor Cyan
    } else {
        $tempClone = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-core-" + [guid]::NewGuid().ToString('N'))
        Write-Host "Shallow-cloning $CoreRemote ($Branch)..." -ForegroundColor Cyan
        git clone --depth 1 --branch $Branch $CoreRemote $tempClone
        if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
        $srcNvim = Join-Path $tempClone 'nvim'
        if (-not (Test-Path $srcNvim)) { throw "cloned Core has no nvim/ tree" }
    }

    # --- mirror source -> target, preserving the local lazy-lock.json ---------
    # robocopy /MIR makes the target match the source (so deletions in Core
    # propagate). /XF lazy-lock.json keeps the env-specific lockfile out of the
    # sync AND protects it from the mirror purge. robocopy exit codes 0-7 are
    # success; >=8 is a real error.
    Write-Host 'Syncing nvim/ ...' -ForegroundColor Cyan
    robocopy $srcNvim $Target /MIR /XF lazy-lock.json /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy reported errors (exit $LASTEXITCODE)" }

    Write-Host ''
    Write-Host 'nvim/ synced from Core. Review and commit:' -ForegroundColor Green
    Write-Host "  git -C `"$RepoRoot`" diff --stat nvim/" -ForegroundColor DarkGray
    Write-Host "  git -C `"$RepoRoot`" add nvim/ ; git -C `"$RepoRoot`" commit -m 'sync nvim from core'" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Known Windows wart: Core keymaps.lua <leader>rc opens ~/.config/nvim/init.lua,' -ForegroundColor DarkYellow
    Write-Host 'but Windows nvim reads %LOCALAPPDATA%\nvim. Harmless; that one keymap points' -ForegroundColor DarkYellow
    Write-Host 'at the wrong path on the host. Left verbatim to keep the sync a clean copy.' -ForegroundColor DarkYellow
}
finally {
    if ($tempClone -and (Test-Path $tempClone)) {
        Remove-Item $tempClone -Recurse -Force -ErrorAction SilentlyContinue
    }
}
