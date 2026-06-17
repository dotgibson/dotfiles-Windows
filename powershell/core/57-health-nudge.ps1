# ============================================================================
#  core/57-health-nudge.ps1  -  one-line "core tools missing" nudge at startup.
#
#  A fresh or half-provisioned host silently loses ls/cat/z and the prompt when
#  the Rust/CLI toolchain isn't installed yet — with no hint until you happen to
#  run dotfiles-doctor. This prints a SINGLE line (once per shell) naming what's
#  missing and pointing at doctor, then gets out of the way (U10).
#
#  On a fully-provisioned box nothing is missing, so it's completely silent — the
#  cost is a handful of cheap Get-Command probes. Suppressed under FAST_START
#  (lean shells), and the message routes through Write-DotWarn so NO_COLOR /
#  DOTFILES_ASCII are honoured. The message itself is built by the pure
#  Get-DotToolNudge (core/05-lib.ps1), so the wording is unit-tested.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: (none)
# requires: Get-DotToolNudge, Test-Cmd, Write-DotWarn

if ($env:FAST_START -eq '1') { return }

# The handful whose absence most degrades the cross-fleet shell feel. Deliberately
# shorter than doctor's full probe — this is a fast startup hint, not an audit.
$essential = 'git', 'starship', 'zoxide', 'fzf', 'rg', 'fd', 'bat', 'eza', 'nvim'
$missing = @($essential | Where-Object { -not (Test-Cmd $_) })

$nudge = Get-DotToolNudge $missing
if ($nudge) { Write-DotWarn $nudge 'install the toolchain: .\packages\Install-Packages.ps1' }
