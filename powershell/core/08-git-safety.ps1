# ============================================================================
#  core/08-git-safety.ps1  -  make shell-spawned git FAIL FAST, never hang
#
#  The problem this closes: git subprocesses that BLOCK forever instead of
#  exiting, then pile up. On the Windows host git gets spawned a lot without you
#  asking — starship's git_* modules on every prompt render, the background
#  `scoop update` bucket pulls in 15-update.ps1, the daily maint job. Any one of
#  those can wedge on an INTERACTIVE credential prompt: git's own terminal prompt,
#  or a Git Credential Manager dialog. In a non-interactive context (a background
#  ThreadJob, a prompt-time probe) there's nobody to answer, so git.exe waits...
#  and the next prompt spawns another, and another — hundreds of orphaned git.exe
#  that hold the git binary busy so `scoop update git` / `winget upgrade Git.Git`
#  can't replace it. (starship's command_timeout, pinned in starship.toml, reaps
#  the read-only prompt-git that wedges on a slow FS; this fragment handles the
#  other half: git that would block waiting for AUTH input.)
#
#  Fix: force git to error out instead of prompt.
#    GIT_TERMINAL_PROMPT=0  git never blocks on its own terminal prompt
#                           (credentials, host-key confirmation) — it fails fast.
#    GCM_INTERACTIVE=Never  Git Credential Manager returns "no credential" rather
#                           than popping a window / waiting.
#  Set as early as possible (08, before 15-update's background git and before the
#  prompt tools in 10-tools) so every git the shell spawns inherits it.
#
#  Escape hatch: set DOTFILES_GIT_ALLOW_PROMPT=1 in the User environment (BEFORE
#  the shell starts) to keep interactive git auth prompting. A value the user has
#  ALREADY exported for either variable is honoured and never overridden.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: Reset-StuckGit
# requires: Write-DotHost, Write-DotOk

if ($env:DOTFILES_GIT_ALLOW_PROMPT -ne '1') {
    if (-not $env:GIT_TERMINAL_PROMPT) { $env:GIT_TERMINAL_PROMPT = '0' }
    if (-not $env:GCM_INTERACTIVE)     { $env:GCM_INTERACTIVE = 'Never' }
}

# Reset-StuckGit (alias: git-reap) — kill orphaned git / credential-helper
# processes left behind by a wedge, so a locked git binary can be updated. This
# is the manual cleanup for a pile that already happened; the env vars above stop
# new ones forming. -WhatIf previews without killing.
function Reset-StuckGit {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()

    $procs = @(Get-Process -Name git, git-remote-https, git-credential-manager -ErrorAction SilentlyContinue)
    if (-not $procs) { Write-DotOk 'no stray git processes to reap.'; return }

    Write-DotHost ("found {0} git-related process(es) still running." -f $procs.Count) -Color Yellow
    $killed = 0
    foreach ($p in $procs) {
        if ($PSCmdlet.ShouldProcess("$($p.ProcessName) (PID $($p.Id))", 'Stop-Process')) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $killed++ } catch { }
        }
    }
    Write-DotOk ("reaped {0} of {1}. now: scoop update git   (or winget upgrade Git.Git)" -f $killed, $procs.Count)
}
Set-Alias git-reap Reset-StuckGit -Scope Global
