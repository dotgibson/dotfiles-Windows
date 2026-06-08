# psmux-menu.ps1 — prefix+w session/window switcher (host port of core/tmux-menu.sh).
# Lists every session and its windows; fzf-pick jumps there. Invoked via:
#   bind w display-popup -E -w 40% -h 50% "pwsh ... -File ~/.config/psmux/scripts/psmux-menu.ps1"
#
# The bash original also surfaced an ~/engagements section — that's DROPPED here on
# purpose: the Windows host is the productivity layer, engagements live on the Kali
# station. So this is pure session/window navigation.
#
# Rows are "display<TAB>target"; fzf shows only the display column (--with-nth 1)
# and we switch to the target field of the chosen line.

$ErrorActionPreference = 'SilentlyContinue'
if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }

$rows = [System.Collections.Generic.List[string]]::new()
foreach ($s in (psmux list-sessions -F '#S' 2>$null | Where-Object { $_ -and $_ -notmatch '^_popup_' })) {
    $rows.Add("$s`t$s")
    foreach ($w in (psmux list-windows -t $s -F '#I:#W' 2>$null)) {
        $idx = ($w -split ':', 2)[0]
        $rows.Add("    $s`:$w`t$s`:$idx")
    }
}
if ($rows.Count -eq 0) { return }

$sel = $rows | fzf --reverse --prompt 'switch > ' --delimiter "`t" --with-nth 1
if (-not $sel) { return }

$target = ($sel -split "`t")[1]
psmux switch-client -t $target
