# psmux-sesh.ps1 — prefix+f sessionizer (host port of core/tmux-sesh.sh).
# Pick a directory (zoxide frecency + common project roots), then attach-or-create
# a psmux session named for it. Invoked via:
#   bind f display-popup -E -w 55% -h 65% "pwsh ... -File ~/.config/psmux/scripts/psmux-sesh.ps1"
#
# NOTE: the fleet's `sesh` (joshmedeski/sesh) is a tmux-in-WSL tool and isn't on
# the host, so this is the find+fzf fallback rebuilt natively — zoxide-aware, the
# same role `sesh list` plays inside WSL. zoxide IS on the host (scoopfile).

$ErrorActionPreference = 'SilentlyContinue'
if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }

$dirs = [System.Collections.Generic.List[string]]::new()

# zoxide's known directories (frecency-ranked), if present
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    zoxide query -l 2>$null | ForEach-Object { if ($_) { $dirs.Add($_) } }
}
# common project roots, one level deep
foreach ($root in @("$HOME\Projects", "$HOME\dev", "$HOME\work", "$HOME\.config")) {
    if (Test-Path $root) {
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $dirs.Add($_.FullName) }
    }
}
if ($dirs.Count -eq 0) { return }

$pick = $dirs | Sort-Object -Unique |
    fzf --reverse --prompt 'session > ' `
        --preview 'eza --icons --tree --level=1 --color=always {}'
if (-not $pick) { return }

# session name = leaf dir, lowercased, spaces/dots -> underscores (matches Core)
$name = (Split-Path $pick -Leaf).ToLower() -replace '[ .]', '_'

psmux has-session -t $name 2>$null
if ($LASTEXITCODE -ne 0) { psmux new-session -d -s $name -c $pick }
psmux switch-client -t $name
