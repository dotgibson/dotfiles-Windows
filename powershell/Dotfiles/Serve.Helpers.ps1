# ============================================================================
#  Serve.Helpers.ps1  -  pure bind/url planning for `serve`, owned by the
#  Dotfiles module (B13).
#
#  `serve` (core/20-functions.ps1) binds every interface on purpose, for ad-hoc
#  LAN file transfer (parity with Core's `serve`). B13 adds an opt-in
#  localhost-only mode (`serve -Local`) WITHOUT changing that default. The pure
#  decision — which `--bind` args to hand `python -m http.server`, and which URL
#  to advertise — lives here so it's unit-tested without spawning a server; the
#  fragment keeps the host I/O (LAN-IP lookup, banner, python spawn).
# ============================================================================

# --- Get-DotServePlan ---------------------------------------------------------
# Given a port, the localhost-only switch, and the already-resolved LAN IP (or
# $null/'' when none was found), return the bind arguments for the python server
# and the URL to advertise:
#   -Local  -> bind 127.0.0.1, advertise http://127.0.0.1:<port>/   (scope 'local')
#   default -> bind every interface (no --bind), advertise the LAN URL when an
#              IP is known, else $null                               (scope 'lan')
# Keeping the LAN-IP lookup in the caller leaves this host-independent and pure.
function Get-DotServePlan {
    [OutputType([pscustomobject])]
    param(
        [int]$Port = 8000,
        [switch]$Local,
        [string]$LanIp
    )
    if ($Local) {
        return [pscustomobject]@{
            Scope    = 'local'
            BindArgs = @('--bind', '127.0.0.1')
            Url      = "http://127.0.0.1:$Port/"
        }
    }
    $url = if ($LanIp) { "http://${LanIp}:$Port/" } else { $null }
    return [pscustomobject]@{
        Scope    = 'lan'
        BindArgs = @()
        Url      = $url
    }
}
