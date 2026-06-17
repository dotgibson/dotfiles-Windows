# ============================================================================
#  core/40-op.ps1  -  1Password CLI helpers (Windows port of Core's zsh/op.zsh)
#
#  The `op` CLI is cross-platform, so these mirror the zsh helpers 1:1. Install
#  it with: winget install -e --id AgileBits.1Password.CLI  (in winget.json).
#  If `op` isn't on PATH, this file defines nothing.
#  Docs: https://developer.1password.com/docs/cli
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: opsecret, openv, optoken, opssh
# requires: Write-DotOk

if (-not (Get-Command op -ErrorAction SilentlyContinue)) { return }

# opsecret — fetch a secret by vault/item/field path
#   opsecret 'Personal/AWS/access_key_id'
function opsecret {
    param([Parameter(Mandatory)][string]$Path)
    op read "op://$Path"
}

# openv — run a command with secrets injected from a .env.op template
#   openv .env.op npm run dev   (.env.op format: KEY=op://vault/item/field)
function openv {
    param([Parameter(Mandatory)][string]$EnvFile)
    if ($args.Count -eq 0) { Write-Host 'Usage: openv <env-template-file> <command...>'; return }
    op run --env-file="$EnvFile" -- @args
}

# optoken — copy a TOTP code to the clipboard
#   optoken 'Personal/GitHub'
function optoken {
    param([Parameter(Mandatory)][string]$Item)
    (op item get $Item --otp) | Set-Clipboard
    Write-DotOk 'TOTP copied to clipboard'
}

# opssh — list SSH keys stored in 1Password
function opssh {
    op item list --categories 'SSH Key' --format table
}

