# ============================================================================
#  core/10-tools.ps1  -  prompt, history, completion, fuzzy nav
#  Keeps the host's terminal feel identical to the rest of the fleet.
# ============================================================================

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
        $sensitive = '(?i)(password|passwd|secret|token|api[_-]?key|-AsPlainText|ConvertTo-SecureString|op read|op item)'
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
if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }

# --- starship prompt (cross-shell - same starship.toml as the fleet) ----------
# Force the repo config to win over any inherited/persistent STARSHIP_CONFIG.
# Only point at it if the file actually exists, so we never aim starship at a
# missing path. init is in its own try so a hiccup can't take down the rest.
if (Test-Cmd starship) {
    $starshipCfg = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'starship\starship.toml' } else { $null }
    if ($starshipCfg -and (Test-Path $starshipCfg)) {
        $env:STARSHIP_CONFIG = $starshipCfg
    }
    try { Invoke-Expression (&starship init powershell) }
    catch { Write-Warning "starship init failed: $_" }
}

# --- zoxide (smarter cd; `z foo`, `zi` for interactive) -----------------------
if (Test-Cmd zoxide) {
    Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) })
}

# --- fzf + PSFzf (Ctrl+t files, Ctrl+r history, Alt+c cd) ---------------------
if ((Test-Cmd fzf) -and (Get-Module -ListAvailable PSFzf)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border --info=inline'
    if (Test-Cmd fd) { $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git' }
}

# --- atuin (shell history sync/search; optional, if installed) ----------------
if (Test-Cmd atuin) {
    Invoke-Expression (& { (atuin init powershell | Out-String) })
}

# --- carapace (multi-shell completions; optional) -----------------------------
if (Test-Cmd carapace) {
    $env:CARAPACE_BRIDGES = 'powershell'
    Invoke-Expression (& { (carapace _carapace powershell | Out-String) })
}

