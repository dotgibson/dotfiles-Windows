# ============================================================================
#  core/10-tools.ps1  -  prompt, history, completion, fuzzy nav
#  Keeps the host's terminal feel identical to the rest of the fleet.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: Get-InitCache, Clear-InitCache, shell-bench, prof-trace
# requires: Get-DotStringSha256, Test-Cmd, Test-SensitiveHistoryLine, Write-DotErr, Write-DotHost, Write-DotWarn

# --- FAST_START escape hatch --------------------------------------------------
# Skips ALL the heavy prompt/history/completion init in this fragment. The cheap
# fragments (aliases, functions, op, psmux defs) still load, so the shell stays
# usable - you just drop to the stock PowerShell prompt with no starship/zoxide/
# atuin/carapace wiring. `return` here ends only this dot-sourced fragment; the
# loader in profile.ps1 carries on to the next one.
#
# FAST_START is read from the ENVIRONMENT at profile-load time, so it must exist
# *before* pwsh starts - setting it in local.ps1 is too late (local loads last).
#   one lean child shell:   $env:FAST_START='1'; pwsh        # child inherits it
#   always lean on this box: [Environment]::SetEnvironmentVariable('FAST_START','1','User')
if ($env:FAST_START -eq '1') { return }

# --- idempotency sentinels ----------------------------------------------------
# `reload` (. $PROFILE) re-dot-sources this fragment. The four `init` calls below
# each shell out to an external binary and inject prompt/keybind hooks; re-running
# them on every reload wastes time and can stack hooks. Track what's already wired
# in a global so a reload is a no-op for the expensive bits. Using $global: (not
# $script:) means this also holds if the fragment is re-sourced on its own.
if (-not $global:DotfilesInit) { $global:DotfilesInit = @{} }

# --- load tracer (DOTFILES_PROFILE_TRACE=1) -----------------------------------
# One stopwatch, lapped after each heavy step below, so the trace table breaks
# this fragment's cost down by tool instead of reporting one lump. No-op unless
# tracing is on. (Reads $script: state that resolves to this dot-sourced
# fragment's scope; Add-DotfilesTrace is global.)
if ($global:DotfilesTraceOn) { $script:__tsw = [System.Diagnostics.Stopwatch]::StartNew(); $script:__tlast = 0.0 }
function script:__lap {
    param([string]$Name)
    if (-not $global:DotfilesTraceOn) { return }
    $now = $script:__tsw.Elapsed.TotalMilliseconds
    Add-DotfilesTrace "10-tools: $Name" ($now - $script:__tlast)
    $script:__tlast = $now
}

# --- PSReadLine: history, prediction, keybinds --------------------------------
# PSReadLine ships with PowerShell 7. Configure it for a zsh-like feel.
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    # CompletionPredictor (managed in packages/modules.ps1) registers itself as a
    # PSReadLine predictor plugin on import. Without this import the "Plugin" half
    # of HistoryAndPlugin below has no source and only history predictions show.
    if (Get-Module -ListAvailable CompletionPredictor) {
        try { Import-Module CompletionPredictor -ErrorAction Stop } catch { }
    }
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        Set-PSReadLineOption -PredictionViewStyle ListView
      } catch {
          # predictions unavailable in this host - carry on
        }
    Set-PSReadLineOption -MaximumHistoryCount 50000

    # Never persist obviously sensitive one-liners to the history file. This is
    # the PSReadLine analog of Core's HISTORY_IGNORE (history.zsh): the line is
    # still usable in the session, it just isn't written to disk. Returning
    # 'MemoryOnly' keeps it out of the saved file; 'None' would drop it entirely.
    # The decision lives in Test-SensitiveHistoryLine (core/05-lib.ps1) so it is
    # unit-tested and word-boundaried — the bare `pwd` command is NOT dropped.
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        if (Test-SensitiveHistoryLine $line) { return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly }
        return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    }

    # Up/Down do prefix-based history search (type `git ` then Up)
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    # Ctrl+arrow word movement; Tab = menu complete
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
}
__lap 'PSReadLine'

# --- Terminal-Icons (file/dir glyphs for Get-ChildItem output) ----------------
# OFF by default: importing Terminal-Icons costs ~1s every shell, and it only
# themes RAW Get-ChildItem/dir output — your ls/ll/la already render icons via
# `eza --icons`, so you almost never see Terminal-Icons output. Opt in by setting
# the env var (User scope, so it's present at shell start — local.ps1 loads too
# late): [Environment]::SetEnvironmentVariable('DOTFILES_TERMINAL_ICONS','1','User')
# Try/catch: the manifest can exist while the .psm1 it points at is missing.
if ($env:DOTFILES_TERMINAL_ICONS -eq '1' -and (Get-Module -ListAvailable Terminal-Icons)) {
    try   { Import-Module Terminal-Icons -ErrorAction Stop }
    catch { Write-DotWarn 'Terminal-Icons failed to load' 'reinstall: Install-Module Terminal-Icons -Scope CurrentUser -Force -AllowClobber' }
}
__lap 'Terminal-Icons'

# --- init-output cache (cold-start speed) -------------------------------------
# starship/zoxide/mise/atuin/carapace each spawn a subprocess just to PRINT their
# shell-integration script, which we then evaluate. Process spawn is the slow part
# on Windows, so cache that text to a file and re-spawn only when the tool's own
# binary is newer than the cache (i.e. after a scoop upgrade). The cache file is
# dot-sourced by the CALLER at global scope (this fragment runs global), so prompt
# hooks / key handlers register exactly as they did with Invoke-Expression.
#   Get-InitCache returns the path to a ready-to-source file (or $null on failure,
#   so each call site can fall back). Bust the whole cache with `init-cache-clear`.
$global:DotfilesInitCacheDir = Join-Path $env:LOCALAPPDATA 'dotfiles\init-cache'
function global:Get-InitCache {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Generate
    )
    $src = (Get-Command $Name -ErrorAction SilentlyContinue).Source
    $cacheFile = Join-Path $global:DotfilesInitCacheDir "$Name.ps1"

    # The cache key has TWO inputs, so a hit means BOTH the tool and the recipe are
    # unchanged:
    #   • binary mtime  — a scoop/winget upgrade rewrites the exe and bumps its
    #                     mtime, so a new tool version regenerates (version drift).
    #   • generator hash — a SHA-256 of THIS call's scriptblock text, stored as a
    #                     marker comment on the cache file's first line. Editing the
    #                     flags here (e.g. `zoxide init powershell --cmd cd`) changes
    #                     the hash, so the stale cache self-busts on the next shell
    #                     instead of silently serving the old init until someone
    #                     remembers `init-cache-clear` (B2).
    $genHash = if (Get-Command Get-DotStringSha256 -ErrorAction SilentlyContinue) {
        Get-DotStringSha256 $Generate.ToString()
    } else { $null }
    $marker = "# initcache-hash: $genHash"

    $stale = $true
    if ((Test-Path $cacheFile) -and $src -and (Test-Path $src)) {
        $mtimeOk = (Get-Item $cacheFile).LastWriteTimeUtc -ge (Get-Item $src).LastWriteTimeUtc
        # First line carries the generator hash; reuse only when it still matches.
        # When hashing is unavailable (05-lib didn't load), fall back to mtime only.
        $hashOk = if ($null -eq $genHash) { $true }
                  else { (Get-Content $cacheFile -TotalCount 1 -ErrorAction SilentlyContinue) -eq $marker }
        $stale = -not ($mtimeOk -and $hashOk)
    }
    if ($stale) {
        try {
            if (-not (Test-Path $global:DotfilesInitCacheDir)) {
                New-Item -ItemType Directory -Force -Path $global:DotfilesInitCacheDir | Out-Null
            }
            $out = (& $Generate | Out-String)
            if ([string]::IsNullOrWhiteSpace($out)) { return $null }
            # Prepend the marker (a PowerShell comment, so dot-sourcing ignores it).
            $payload = if ($genHash) { $marker + "`n" + $out } else { $out }
            Set-Content -Path $cacheFile -Value $payload -Encoding utf8
        } catch { return $null }
    }
    return $cacheFile
}

# init-cache-clear: drop every cached init script (they regenerate on next start).
# Use after changing a tool's flags here, or if an init ever caches badly.
function global:Clear-InitCache {
    if (Test-Path $global:DotfilesInitCacheDir) {
        Remove-Item (Join-Path $global:DotfilesInitCacheDir '*.ps1') -Force -ErrorAction SilentlyContinue
    }
    Write-DotHost 'init cache cleared (regenerates on next shell start)' -Color Green
}
Set-Alias init-cache-clear Clear-InitCache -Scope Global

# shell-bench: time a cold pwsh start (full profile) N times. Use this to decide
# whether any of the above is worth tuning further — measure, don't guess.
#   shell-bench        # 5 runs
#   shell-bench 10
function global:shell-bench {
    param([int]$Runs = 5)
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-DotErr 'pwsh not found' 'install it: scoop install pwsh'; return }
    1..$Runs | ForEach-Object {
        (Measure-Command { & $pwshPath -NoLogo -Command exit }).TotalMilliseconds
    } | Measure-Object -Average -Minimum -Maximum |
        Select-Object @{n='Runs';e={$Runs}}, @{n='Min_ms';e={[math]::Round($_.Minimum)}},
                      @{n='Avg_ms';e={[math]::Round($_.Average)}}, @{n='Max_ms';e={[math]::Round($_.Maximum)}}
}

# prof-trace: load the FULL profile in a clean child with tracing on, and show the
# slowest-first breakdown. Instead of relying on the child's console output (which
# can be swallowed by the -Command/-NoExit/host-stream chain — the "prints nothing"
# bug), the child WRITES the table to a temp file and the parent reads it back on
# its own output stream. Robust regardless of how the child's console behaves.
#   • PSMUX_NO_AUTOLAUNCH=1 — psmux can't grab the trace child.
#   • The child writes to $env:DOTFILES_TRACE_OUT (inherited from us), so there's
#     no string-escaping of paths into the command.
#   • If the file comes back empty/missing, that itself tells us the profile didn't
#     populate the trace (vs. an output-plumbing problem) — and we say so.
function global:prof-trace {
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-DotErr 'pwsh not found' 'install it: scoop install pwsh'; return }
    $out = Join-Path $env:TEMP 'dotfiles-proftrace.txt'
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    $env:DOTFILES_TRACE_OUT = $out
    try {
        & $pwshPath -NoProfile -Command {
            $env:DOTFILES_PROFILE_TRACE = '1'
            $env:PSMUX_NO_AUTOLAUNCH    = '1'
            . $PROFILE
            if ($global:DotfilesTrace -and $global:DotfilesTrace.Count) {
                $global:DotfilesTrace | Sort-Object ms -Descending |
                    Format-Table -AutoSize | Out-String -Width 200 |
                    Set-Content -Path $env:DOTFILES_TRACE_OUT -Encoding utf8
            } else {
                Set-Content -Path $env:DOTFILES_TRACE_OUT -Encoding utf8 `
                    -Value '(trace empty — profile loaded but DotfilesTrace was never populated)'
            }
        }
    } finally {
        Remove-Item Env:DOTFILES_TRACE_OUT -ErrorAction SilentlyContinue
    }
    if (Test-Path $out) {
        Write-DotHost "`nprofile load trace (slowest first):" -Color Cyan
        Get-Content $out
    } else {
        Write-DotWarn 'prof-trace: child wrote no file — the profile likely errored before the trace ran.'
        Write-DotHost  'Fallback (loads the profile the plain way, no -Command indirection):' -Color DarkGray
        Write-DotHost  "  `$env:DOTFILES_PROFILE_TRACE='1'; `$env:PSMUX_NO_AUTOLAUNCH='1'; pwsh -NoLogo" -Color DarkGray
    }
}

# --- starship prompt (cross-shell - same starship.toml as the fleet) ----------
# Force the repo config to win over any inherited/persistent STARSHIP_CONFIG.
# Only point at it if the file actually exists, so we never aim starship at a
# missing path. init is in its own try so a hiccup can't take down the rest.
if ((Test-Cmd starship) -and -not $global:DotfilesInit.Starship) {
    $starshipCfg = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'starship\starship.toml' } else { $null }
    if ($starshipCfg -and (Test-Path $starshipCfg)) {
        $env:STARSHIP_CONFIG = $starshipCfg
    }
    try {
        $cf = Get-InitCache -Name starship -Generate { starship init powershell }
        if ($cf) { . $cf } else { Invoke-Expression (&starship init powershell) }   # fallback: never lose the prompt
        $global:DotfilesInit.Starship = $true
    } catch { Write-DotWarn "starship init failed: $_" }
}
__lap 'starship'

# --- zoxide (smarter cd; `z foo`, `zi` for interactive) -----------------------
if ((Test-Cmd zoxide) -and -not $global:DotfilesInit.Zoxide) {
    $cf = Get-InitCache -Name zoxide -Generate { zoxide init powershell --cmd cd }
    if ($cf) { . $cf } else { Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) }) }
    $global:DotfilesInit.Zoxide = $true
}
__lap 'zoxide'

# --- fzf + PSFzf (Ctrl+t files, Ctrl+r history, Alt+c cd) ---------------------
# Ctrl+R ownership: when atuin is installed it loads AFTER this and rebinds Ctrl+R
# to its own (richer) history search — so binding it here too just gets clobbered,
# making the winner a matter of load order. Make the intent explicit: hand Ctrl+R
# to PSFzf ONLY when atuin isn't present; otherwise PSFzf keeps Ctrl+T and atuin
# owns Ctrl+R cleanly.
if ((Test-Cmd fzf) -and (Get-Module -ListAvailable PSFzf)) {
    Import-Module PSFzf
    if (Test-Cmd atuin) {
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t'
    } else {
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    }
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border --info=inline'
    if (Test-Cmd fd) { $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git' }
}
__lap 'fzf/PSFzf'

# --- mise (runtime/tool version manager; shims + path setup) ------------------
# `mise activate` injects shims and a prompt hook that keeps the active tool
# versions consistent with the nearest .mise.toml / .tool-versions file. This is
# the Windows equivalent of the Core zsh `mise activate zsh` call.
if ((Test-Cmd mise) -and -not $global:DotfilesInit.Mise) {
    $cf = Get-InitCache -Name mise -Generate { mise activate pwsh }
    if ($cf) { . $cf } else { Invoke-Expression (& { (mise activate pwsh | Out-String) }) }
    $global:DotfilesInit.Mise = $true
}
__lap 'mise'

# --- atuin (shell history sync/search; optional, if installed) ----------------
if ((Test-Cmd atuin) -and -not $global:DotfilesInit.Atuin) {
    $cf = Get-InitCache -Name atuin -Generate { atuin init powershell }
    if ($cf) { . $cf } else { Invoke-Expression (& { (atuin init powershell | Out-String) }) }
    $global:DotfilesInit.Atuin = $true
}
__lap 'atuin'

# --- carapace (multi-shell completions; optional) -----------------------------
# OFF by default: generating carapace's completion bridge costs ~1.5s on a cold
# shell. pwsh's native completion + CompletionPredictor + atuin cover most needs.
# Opt in (User scope, present at shell start — local.ps1 loads too late):
#   [Environment]::SetEnvironmentVariable('DOTFILES_CARAPACE','1','User')
# When enabled, the init is cached (Get-InitCache) so warm shells skip the spawn.
if ($env:DOTFILES_CARAPACE -eq '1' -and (Test-Cmd carapace) -and -not $global:DotfilesInit.Carapace) {
    $env:CARAPACE_BRIDGES = 'powershell'
    $cf = Get-InitCache -Name carapace -Generate { carapace _carapace powershell }
    if ($cf) { . $cf } else { Invoke-Expression (& { (carapace _carapace powershell | Out-String) }) }
    $global:DotfilesInit.Carapace = $true
}
__lap 'carapace'

# --- navi (interactive cheatsheet; Ctrl+G to open the widget) -----------------
# navi's shell widget binds Ctrl+G to open an interactive cheatsheet picker.
# We deliberately do NOT bind Ctrl+T/Ctrl+R (those belong to PSFzf/atuin above).
# Guard: only invoke if the widget output is non-empty. The current scoop build
# of navi does not support `widget powershell` and returns nothing — in that
# case we skip silently rather than erroring. `navi` itself still works as a
# standalone command; you just won't get the Ctrl+G keybind.
#
# CACHED like the other inits (Get-InitCache): `navi widget powershell` is a
# subprocess spawn, and this was the ONLY tool init still paying that on EVERY
# new shell/pane (starship/zoxide/mise/atuin all cache). Caching it makes each
# split/new-window cheaper. The Shim-noise filter runs inside the generator so
# only clean output is cached; an empty widget (broken build) yields $null and we
# skip, exactly as before. Cache busts when the navi binary is upgraded.
if ((Test-Cmd navi) -and -not $global:DotfilesInit.Navi) {
    try {
        $cf = Get-InitCache -Name navi -Generate {
            (& navi widget powershell 2>$null) -split "`n" |
                Where-Object { $_ -notmatch '^Shim:' }
        }
        if ($cf) { . $cf; $global:DotfilesInit.Navi = $true }
    } catch { }
}
__lap 'navi'
