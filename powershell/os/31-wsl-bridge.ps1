# ============================================================================
#  os/31-wsl-bridge.ps1  -  the seam between the host and your WSL distros
#
#  Your Linux dotfiles (Core / Debian / Kali) live INSIDE WSL and configure
#  themselves there. This file is the host-side glue: jump into a distro,
#  cross the filesystem boundary cleanly, and surface the host IP (handy when
#  a service in WSL needs to be reachable from the host LAN - see
#  wsl/windows.wslconfig.example for mirrored networking).
#
#  The pure path translation (ConvertTo-WslPath) now lives in the Dotfiles module
#  (powershell/Dotfiles/Wsl.Helpers.ps1), imported by the profile BEFORE this
#  fragment, so it stays available and unit-tested even on a host without wsl.
#  The wsl-dependent verbs below call it via that module export.
# ============================================================================

if (-not (Test-Cmd wsl)) { return }

# --- distro shortcuts ---------------------------------------------------------
function kali   { wsl -d kali-linux @args }
function debian { wsl -d Debian @args }
function wsls   { wsl --list --verbose }       # status of all distros
function wslip  { wsl -d kali-linux -- hostname -I }   # the distro's IP(s)

# --- drop into a distro at the *current* Windows directory --------------------
# `cdwsl` translates C:\path -> /mnt/c/path (via ConvertTo-WslPath) and starts a
# shell there; a non-drive CWD just opens the distro at its default location.
function cdwsl {
    param([string]$Distro = 'kali-linux')
    $wslPath = ConvertTo-WslPath (Get-Location).Path
    if ($wslPath) { wsl -d $Distro --cd $wslPath }
    else          { wsl -d $Distro }
}

# --- host primary IPv4 --------------------------------------------------------
# With networkingMode=mirrored, the host and WSL share interfaces, so the
# host's LAN IP is the address other machines use to reach a service running
# in WSL. This surfaces it fast.
function hostip {
    (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.PrefixOrigin -in 'Dhcp','Manual' -and $_.IPAddress -notlike '169.254.*' } |
        Sort-Object SkipAsSource |
        Select-Object -First 1 -ExpandProperty IPAddress)
}

# --- open the current Windows folder inside WSL's $HOME quickly ---------------
function wslhome { wsl -d kali-linux --cd '~' }

# --- restart the WSL subsystem (clears stuck mounts / network) ----------------
function wsl-restart { wsl --shutdown; Write-Host 'WSL shut down; next `wsl` call cold-starts it.' -ForegroundColor Yellow }
