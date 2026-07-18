# ============================================================================
#  os/48-core.ps1  -  the `core` front door, for cross-fleet muscle memory.
#
#  On the Unix side (dotfiles-core) the umbrella verb is `core`:
#      core help | core doctor | core version | core update
#  with standalone twins `core-help` / `core-doctor` / `core-version`. A cross-
#  platform operator moving between WSL-zsh and Windows-pwsh in the same day
#  should reach for the SAME command on both — so this host replicates that
#  surface natively. These are thin dispatchers over the host's existing verbs
#  (`dothelp`, `dotfiles-doctor`, `up`), which stay canonical and unchanged; the
#  old names still work. Parity is pinned by dotfiles-core's PARITY.md +
#  scripts/parity-check.sh so the two shells can't drift.
#
#  Loads from os/ (not core/) on purpose: `core doctor` bridges to the host's
#  `dotfiles-doctor` (os/45-doctor.ps1), so this must load AFTER it for the load
#  contract to resolve.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: core, core-doctor, core-help, core-version
# requires: dothelp, dotfiles-doctor, Get-DotLevenshtein, Get-DotRepoRevision, Get-DotRepoVersionDetail, up, Write-DotErr, Write-DotHost

# Standalone twins — mirror Core's core-help / core-doctor / core-version. Thin
# pass-throughs (splat all args) to the host's native verbs, which remain the
# real implementations; these add the fleet-consistent NAME, not new behaviour.
function global:core-doctor { dotfiles-doctor @args }
function global:core-help   { dothelp @args }

function global:core-version {
    # Windows has no core.version file (it replicates Core rather than vendoring
    # it), so the "version" of this layer is the repo revision — the SAME detail the
    # doctor's "Repo version" row shows. Resolve it via the shared Get-DotRepoRevision
    # helper (os/45-doctor.ps1) so the git-log/status block lives in exactly one place
    # (C3), then format it with the pure Get-DotRepoVersionDetail.
    $root   = if ($global:DOTFILES) { $global:DOTFILES } else { $env:DOTFILES_WIN }
    $rev    = Get-DotRepoRevision -Root $root
    $detail = if ($rev) { Get-DotRepoVersionDetail -Sha "$($rev.Sha)" -IsDirty $rev.IsDirty -When "$($rev.When)" }
              else       { 'unknown (no git metadata)' }
    Write-DotHost ("dotfiles-Windows {0}" -f $detail) -Color Cyan
}

# `core <verb>` — the umbrella front door. Bare `core` prints the command index
# (like `core` -> the cheat sheet on Unix); an unknown verb gets a did-you-mean
# + usage. Mirrors dotfiles-core's zsh `core()` dispatcher.
function global:core {
    $verbs = @('help', 'doctor', 'version', 'update')
    $sub   = if ($args.Count) { [string]$args[0] } else { '' }
    $rest  = @($args | Select-Object -Skip 1)
    switch -Regex ($sub) {
        '^(|-h|--help|help)$'      { core-help @rest; return }
        '^doctor$'                 { core-doctor @rest; return }
        '^(version|-V|--version)$' { core-version @rest; return }
        '^update$'                 { up @rest; return }
        default {
            Write-DotErr "core: unknown subcommand: $sub"
            $near = $verbs | Sort-Object { Get-DotLevenshtein $sub $_ } | Select-Object -First 1
            if ($near -and (Get-DotLevenshtein $sub $near) -le 3) {
                Write-DotHost ("  did you mean: core {0}?" -f $near) -Color DarkYellow
            }
            Write-DotHost ("  usage: core <{0}>" -f ($verbs -join '|')) -Color DarkGray
            return
        }
    }
}
