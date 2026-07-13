# psmux-url.ps1 — prefix+u URL picker (host port of Core's tmux-fzf-url plugin).
# Scrape URLs from the visible pane + recent scrollback, fuzzy-pick one, and copy it
# to the clipboard (clip.exe, the same sink psmux copy-mode yank uses). Invoked via:
#   bind u display-popup -E "pwsh ... -File ~/.config/psmux/scripts/psmux-url.ps1"
#
# The popup is an OVERLAY, not a pane, so the session's active pane is still the one
# the key was pressed in — `psmux capture-pane -p` targets that pane's content.

$ErrorActionPreference = 'SilentlyContinue'
if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }
if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) { return }

# Capture the visible pane plus recent scrollback (joined wrapped lines with -J).
$buf = psmux capture-pane -p -J -S -2000 2>$null
if (-not $buf) { return }

# Match http(s):// and www. URLs; trim trailing punctuation that commonly abuts a URL.
$rx = [regex]'(?i)((?:https?://|www\.)[^\s"''<>`)\]}]+)'
$urls = [System.Collections.Generic.List[string]]::new()
foreach ($line in ($buf -split "`n")) {
    foreach ($m in $rx.Matches($line)) {
        $u = $m.Groups[1].Value.TrimEnd('.', ',', ';', ':', ')', ']', '}')
        if ($u) { $urls.Add($u) }
    }
}
if ($urls.Count -eq 0) { return }

# Most-recent-on-screen first, de-duplicated while preserving that order.
$seen = @{}
$ordered = [System.Collections.Generic.List[string]]::new()
for ($i = $urls.Count - 1; $i -ge 0; $i--) {
    $u = $urls[$i]
    if (-not $seen.ContainsKey($u)) { $seen[$u] = $true; $ordered.Add($u) }
}

$pick = $ordered | fzf --reverse --prompt 'url > '
if ($pick) { $pick | clip.exe }
