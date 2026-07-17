# psmux-split.ps1 — crash-proof split / new-window launcher for psmux.
# ──────────────────────────────────────────────────────────────────────────────
# THE BUG THIS FIXES: the split binds pass the current pane's directory to the new
# pane as its start-dir (`-c "#{pane_current_path}"`, psmux.reset.conf). When that
# directory is one the freshly-spawned native pwsh can't chdir into — a WSL/UNC
# path (\\wsl.localhost\..., \\wsl$\...) you reached via `cdwsl`, or a since-deleted
# dir — the pane shell dies on entry and psmux tears the pane down. That is the
# "prefix + _ splits, opens, then immediately aborts and closes" report.
#
# THE FIX: don't hand the new pane a directory it can't use. Validate the path and
# fall back to $HOME (always chdir-able) when it isn't a real, local, existing dir.
# UNC paths are rejected outright — even a *reachable* \\wsl$ path is the trigger,
# so home is the safe landing spot, exactly the graceful $HOME fallback we want.
#
# Invoked from psmux.reset.conf via run-shell (proven to work — see the `run` line
# in psmux.conf). psmux expands #{pane_current_path}/#{pane_id} before the shell
# runs, and the child inherits the server env (TMUX/PSMUX_SESSION) so the `psmux`
# call below targets the right server/pane. Uses -NoProfile: this launcher needs
# no profile, so the split costs ~one cold-pwsh parse, off the status render path
# and only on a deliberate keypress (never per-repaint).
# ──────────────────────────────────────────────────────────────────────────────
[CmdletBinding()]
param(
    # psmux verb to run: 'split-window' (the four split binds) or 'new-window' (c).
    [ValidateSet('split-window', 'new-window')]
    [string]$Verb = 'split-window',
    # Extra layout flags for the verb, space-separated (e.g. '-fv', '-h', '-fh').
    [string]$Flags = '',
    # The requested start-dir (psmux passes #{pane_current_path}); may be unusable.
    [string]$Path = '',
    # Target the verb acts on: a pane id (#{pane_id}) for splits, a session
    # (#{session_name}:) for new-window. Empty = let psmux use the current context.
    [string]$Target = ''
)

$ErrorActionPreference = 'SilentlyContinue'

# A directory is safe to hand a new native-pwsh pane only if it EXISTS and is a
# real local (drive-letter) path. UNC / WSL paths (\\... or //...) are the crash
# trigger even when reachable, so treat any UNC path as unusable.
function Test-SafeStartDir {
    param([string]$p)
    if (-not $p) { return $false }
    if ($p -match '^(\\\\|//)') { return $false }               # UNC / \\wsl$ path
    return [bool](Test-Path -LiteralPath $p -PathType Container) # exists + is a dir
}

$startDir = if (Test-SafeStartDir $Path) { $Path } else { $HOME }

$flagArgs = @()
if ($Flags.Trim()) { $flagArgs = $Flags.Trim() -split '\s+' }

$targetArgs = @()
if ($Target) { $targetArgs = @('-t', $Target) }

# One psmux call, always with a directory the new shell can actually enter.
psmux $Verb @flagArgs @targetArgs -c $startDir
