# ============================================================================
#  core/10-tools.ps1  -  prompt, history, completion, fuzzy nav
#  Keeps the host's terminal feel identical to the rest of the fleet.
# ============================================================================

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

# --- PSReadLine: history, prediction, keybinds --------------------------------
# PSReadLine ships with PowerShell 7. Configure it for a zsh-like feel.
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
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
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        $sensitive = '(?i)(password|passwd|pwd|pass|secret|token|api[_-]?key|bearer|authorization|credential|creds|-password|oauth|jwt|op read|op item)'
        if ($line -match $sensitive) { return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly }
        return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    }

    # Up/Down do prefix-based history search (type `git ` then Up)
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    # Ctrl+arrow word movement; Tab = menu complete
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
}

# --- Terminal-Icons (file/dir glyphs for Get-ChildItem output) ----------------
# Wrap in try/catch: the manifest can exist (ListAvailable returns true) while
# the .psm1 it references is missing (corrupted/partial install). If that
# happens the warning tells you exactly how to fix it.
if (Get-Module -ListAvailable Terminal-Icons) {
    try   { Import-Module Terminal-Icons -ErrorAction Stop }
    catch { Write-Warning "Terminal-Icons failed to load — reinstall with: Install-Module Terminal-Icons -Scope CurrentUser -Force -AllowClobber" }
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
    try { Invoke-Expression (&starship init powershell); $global:DotfilesInit.Starship = $true }
    catch { Write-Warning "starship init failed: $_" }
}

# --- zoxide (smarter cd; `z foo`, `zi` for interactive) -----------------------
if ((Test-Cmd zoxide) -and -not $global:DotfilesInit.Zoxide) {
    Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) })
    $global:DotfilesInit.Zoxide = $true
}

# --- fzf + PSFzf (Ctrl+t files, Ctrl+r history, Alt+c cd) ---------------------
if ((Test-Cmd fzf) -and (Get-Module -ListAvailable PSFzf)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border --info=inline'
    if (Test-Cmd fd) { $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git' }
}

# --- mise (runtime/tool version manager; shims + path setup) ------------------
# `mise activate` injects shims and a prompt hook that keeps the active tool
# versions consistent with the nearest .mise.toml / .tool-versions file. This is
# the Windows equivalent of the Core zsh `mise activate zsh` call.
if ((Test-Cmd mise) -and -not $global:DotfilesInit.Mise) {
    Invoke-Expression (& { (mise activate pwsh | Out-String) })
    $global:DotfilesInit.Mise = $true
}

# --- atuin (shell history sync/search; optional, if installed) ----------------
if ((Test-Cmd atuin) -and -not $global:DotfilesInit.Atuin) {
    Invoke-Expression (& { (atuin init powershell | Out-String) })
    $global:DotfilesInit.Atuin = $true
}

# --- carapace (multi-shell completions; optional) -----------------------------
if ((Test-Cmd carapace) -and -not $global:DotfilesInit.Carapace) {
    $env:CARAPACE_BRIDGES = 'powershell'
    Invoke-Expression (& { (carapace _carapace powershell | Out-String) })
    $global:DotfilesInit.Carapace = $true
}

# --- navi (interactive cheatsheet; Ctrl+G to open the widget) -----------------
# navi's shell widget binds Ctrl+G to open an interactive cheatsheet picker.
# We deliberately do NOT bind Ctrl+T/Ctrl+R (those belong to PSFzf/atuin above).
# Guard: only invoke if the widget output is non-empty. The current scoop build
# of navi does not support `widget powershell` and returns nothing — in that
# case we skip silently rather than erroring. `navi` itself still works as a
# standalone command; you just won't get the Ctrl+G keybind.
if ((Test-Cmd navi) -and -not $global:DotfilesInit.Navi) {
    $naviWidget = navi widget powershell 2>$null | Out-String
    if ($naviWidget.Trim()) {
        Invoke-Expression $naviWidget
        $global:DotfilesInit.Navi = $true
    }
}
