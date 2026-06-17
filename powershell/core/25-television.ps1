# ============================================================================
#  core/25-television.ps1  -  television (tv) channel wrappers
#
#  television is a fast, cross-platform fuzzy finder built around "channels"
#  (named data sources: files, text, dirs, git-repos, env, ...). These are
#  one-word verbs over the common channels, in the spirit of the fleet's other
#  fuzzy helpers.
#
#  DELIBERATELY NOT CALLED: `tv init powershell`. Its shell integration binds
#  Ctrl+T and Ctrl+R, and Ctrl+R already belongs to atuin/PSFzf in 10-tools.ps1.
#  We take the named functions only and leave the history keybind alone. If you
#  ever want tv to own Ctrl+T/Ctrl+R, wire `tv init` in local.ps1 and decide
#  there which tool wins.
#
#  Every function is guarded by `Test-Cmd tv` (defined in 00-aliases.ps1), so
#  this fragment is inert on a host where television isn't installed. Channels
#  depend on tv's own config; the built-ins used here ship by default.
#
#  Cross-fleet note: television is cross-platform. If you want zsh parity, the
#  equivalents belong in dotfiles-core (canonical), with this as the PS port.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: tvim, ttext, tcd, trepo, tbranch, tenv
# requires: Test-Cmd

if (Test-Cmd tv) {

    # --- tvim: fuzzy-pick a file (files channel) and open it in nvim ----------
    function tvim {
        $sel = tv @args
        if ($sel) { nvim $sel }
    }

    # --- ttext: fuzzy-search file *contents* (text channel), open in nvim -----
    # television parallel to `fif` (which uses rg+fzf). Keep whichever you like.
    function ttext {
        $sel = tv text @args
        if ($sel) { nvim $sel }
    }

    # --- tcd: fuzzy-pick a directory (dirs channel) and cd into it ------------
    function tcd {
        $sel = tv dirs @args
        if ($sel -and (Test-Path -LiteralPath $sel)) { Set-Location -LiteralPath $sel }
    }

    # --- trepo: fuzzy-pick a git repo (git-repos channel) and cd into it ------
    function trepo {
        $sel = tv git-repos @args
        if ($sel -and (Test-Path -LiteralPath $sel)) { Set-Location -LiteralPath $sel }
    }

    # --- tbranch: fuzzy-pick a git branch and check it out --------------------
    # television parallel to `fbr`. Branch names are cleaned in PowerShell first
    # (strip '* '/'+ ' markers and 'remotes/<remote>/') so the checkout target is
    # already a valid ref, then piped into tv as an ad-hoc list.
    function tbranch {
        $branches = git branch --all 2>$null |
            Where-Object { $_ -notmatch 'HEAD' } |
            ForEach-Object { ($_ -replace '^[*+ ]+', '' -replace 'remotes/[^/]+/', '').Trim() } |
            Sort-Object -Unique
        if (-not $branches) { return }
        $branch = $branches | tv
        if ($branch) { git checkout $branch.Trim() }
    }

    # --- tenv: browse environment variables (env channel) ---------------------
    function tenv { tv env @args }
}
