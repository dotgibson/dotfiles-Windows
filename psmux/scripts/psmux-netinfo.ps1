# psmux-netinfo.ps1 — the "operator" segment of the status line.
# Windows/PowerShell port of dotfiles-core/tmux/scripts/tmux-netinfo.sh, so the
# Windows box shows the same at-a-glance fact as the Unix fleet.
# ──────────────────────────────────────────────────────────────────────────────
# Shows your VPN / tunnel IP (the callback address a reverse shell must reach)
# when a tunnel interface is up — in standout ORANGE — otherwise your primary LAN
# IP in GREEN, otherwise NOTHING. The empty case is what keeps it portable: a box
# with no tunnel and no routable LAN simply renders no pill.
#
# Emits a fully-styled psmux "pill" (its own #[...] colour codes), which psmux
# re-interprets in status-right. Wired up via a #() shell-out in psmux.conf:
#   #(pwsh -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.config\psmux\scripts\psmux-netinfo.ps1)
# psmux caches #() output for `status-interval` seconds, so this runs at most
# once per refresh.
#
# Deliberately tolerant (SilentlyContinue): a status helper must never hard-fail.
# This is the bash original's Linux `ip`/macOS `ipconfig` logic re-expressed with
# the Windows NetTCPIP cmdlets (Get-NetIPAddress / Get-NetAdapter / Find-NetRoute).
# ──────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = 'SilentlyContinue'

# tokyonight-storm palette. Literal hex on purpose: psmux does not expand #{@tn_*}
# inside #[...] (whether in style options or in #() output), and BG is the bar's
# highlight bg (@tn_bg_hl = #292e42) so the pill floats on the bar like the cwd /
# clock pills in psmux.conf.
$BG     = '#292e42'
$ORANGE = '#ff9e64'
$GREEN  = '#9ece6a'

# left/right rounded caps (Nerd Font) — same glyphs as @cap_l / @cap_r
$CAP_L = ''
$CAP_R = ''

function Pill {
    param([string]$Accent, [string]$Text)
    "#[fg=$Accent,bg=$BG]$CAP_L#[fg=$BG,bg=$Accent,bold]$Text#[fg=$Accent,bg=$BG]$CAP_R"
}

# Adapter Name / InterfaceDescription patterns that mean "tunnel"
# (OpenVPN TAP/Wintun, WireGuard, Tailscale, Proton, Nord, generic VPN).
$TunnelPattern = 'WireGuard|Wintun|TAP-Windows|OpenVPN|Tailscale|ProtonVPN|NordLynx|NordVPN|\bVPN\b|\btun\d|\bwg\d'

# Up IPv4 addresses, minus loopback and APIPA (169.254.*).
function Get-Ipv4Up {
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -and
            $_.IPAddress -ne '127.0.0.1' -and
            $_.IPAddress -notlike '169.254.*'
        }
}

# Tunnel interface in priority of "first up tunnel adapter with a v4 address".
function Get-TunnelInfo {
    foreach ($ip in Get-Ipv4Up) {
        $ad = Get-NetAdapter -InterfaceIndex $ip.InterfaceIndex -ErrorAction SilentlyContinue
        if (-not $ad -or $ad.Status -ne 'Up') { continue }
        if (($ad.InterfaceDescription -match $TunnelPattern) -or ($ad.Name -match $TunnelPattern)) {
            $iface = $ad.Name
            if ($iface.Length -gt 14) { $iface = $iface.Substring(0, 14) }
            return [pscustomobject]@{ Iface = $iface; Addr = $ip.IPAddress }
        }
    }
    return $null
}

# Primary LAN IP: the source address the box would use to reach the internet
# (the Windows equivalent of `ip route get 1.1.1.1` -> src).
function Get-LanIp {
    $src = Find-NetRoute -RemoteIPAddress '1.1.1.1' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue |
        Where-Object { $_ -and $_ -ne '127.0.0.1' -and $_ -notlike '169.254.*' } |
        Select-Object -First 1
    if ($src) { return $src }

    # Fallback: first up adapter that has a default gateway.
    $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1
    if ($cfg -and $cfg.IPv4Address) { return $cfg.IPv4Address.IPAddress }
    return $null
}

$tun = Get-TunnelInfo
if ($tun) {
    Pill $ORANGE " $($tun.Iface) $($tun.Addr)"   # shield: you're tunneled
}
else {
    $lan = Get-LanIp
    if ($lan) {
        Pill $GREEN " $lan"                       # ethernet: LAN only
    }
}
