# tmux-netinfo.ps1 — operator-IP pill for the psmux status line.
# Windows-native port of core/tmux/scripts/tmux-netinfo.sh (NOT vendored Core —
# this is a standalone Windows rewrite, invoked by psmux via #()).
#
# Prints a fully-styled tmux pill: the VPN/tunnel IP in ORANGE if a tunnel adapter
# is up (the callback address a reverse shell must reach), else the primary LAN IP
# in GREEN, else NOTHING — so the segment self-hides on a box with neither.
# Output goes to stdout with no trailing newline so psmux's #() embeds it cleanly.
#
# Wired into psmux/.tmux.conf as:
#   #(pwsh -NoProfile -File ~/.tmux/scripts/tmux-netinfo.ps1)
#
# Glyphs/caps are written as `u{XXXX} escapes (named inline) so they survive
# transfer — raw Nerd-Font glyphs get silently stripped. If one shows as tofu,
# your font lacks it; swap the codepoint. Palette is tokyonight-storm.

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# tokyonight-storm (kept in sync with starship.toml + the .tmux.conf @tn_*)
$BG     = '#24283b'
$ORANGE = '#ff9e64'
$GREEN  = '#9ece6a'
$CAP_L  = "`u{e0b6}"   # e0b6 rounded left cap  (match to @cap_l if you change it)
$CAP_R  = "`u{e0b4}"   # e0b4 rounded right cap

function Pill {
    param([string]$Accent, [string]$Text)
    "#[fg=$Accent,bg=default]$CAP_L#[fg=$BG,bg=$Accent,bold] $Text #[fg=$Accent,bg=default]$CAP_R"
}

# Tunnel adapters by InterfaceAlias pattern: WireGuard / OpenVPN(TAP) / Proton /
# Tailscale / generic tunN. Adjust the pattern to your installed VPN clients.
$tunPattern = 'WireGuard|wg\d|OpenVPN|TAP-|Proton|Tailscale|tun\d'

$tun = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' -and
        $_.InterfaceAlias -match $tunPattern
    } | Select-Object -First 1

if ($tun) {
    $out = Pill $ORANGE ("`u{f023} " + $tun.IPAddress)   # f023 lock — tunneled
} else {
    $lan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PrefixOrigin -in 'Dhcp','Manual' -and $_.IPAddress -notlike '169.254.*'
        } | Sort-Object SkipAsSource | Select-Object -First 1 -ExpandProperty IPAddress
    if ($lan) { $out = Pill $GREEN ("`u{f0e8} " + $lan) }  # f0e8 sitemap — LAN only
    else      { $out = '' }
}

[Console]::Out.Write($out)
