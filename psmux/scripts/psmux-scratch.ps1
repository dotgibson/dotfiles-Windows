# psmux-scratch.ps1 — prefix+T scratch-terminal popup (psmux port of core/tmux-scratch.sh).
# A throwaway pwsh in a floating popup, backed by a persistent hidden session so
# its contents survive between opens. Invoked from psmux.conf via:
#   bind T display-popup -E -w 80% -h 80% "pwsh ... -File ~/.config/psmux/scripts/psmux-scratch.ps1"
#
# The bash original also flipped key-table/prefix tricks; those are tmux-internals
# that psmux may not expose, so this sticks to the portable subset (create-if-
# missing + status off + attach), which is all the scratchpad actually needs.

$ErrorActionPreference = 'SilentlyContinue'
$session = '_popup_scratchpad'

psmux has-session -t $session 2>$null
if ($LASTEXITCODE -ne 0) {
    psmux new-session -d -s $session
    psmux set-option -t $session status off 2>$null
}
psmux attach -t $session
