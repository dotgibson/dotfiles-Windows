# ============================================================================
#  os/31-wsl-bridge.ps1  -  the seam between the host and your WSL distros
#
#  Your Linux dotfiles (Core / Debian / Kali) live INSIDE WSL and configure
#  themselves there. This file is the host-side glue: jump into a distro,
#  cross the filesystem boundary cleanly, and surface the host IP (handy when
#  a service in WSL needs to be reachable from the host LAN - see
#  wsl/windows.wslconfig.example for mirrored networking).
# ============================================================================

# --- pure path translation (defined BEFORE the wsl guard so it's always testable)
# C:\Users\me\src -> /mnt/c/Users/me/src. Returns $null for anything that isn't a
# drive-qualified Windows path (UNC share, an already-/mnt path), so callers can
# fall back to a plain shell. Pure: unit-tested in tests/WslBridge.Tests.ps1.
function global:ConvertTo-WslPath {
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WindowsPath)
    if ($WindowsPath -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }
    return $null
}

if (-not (Test-Cmd wsl)) { return }

# --- distro shortcuts ---------------------------------------------------------
function kali   { wsl -d kali-linux @args }
function debian { wsl -d Debian @args }
function wsls   { wsl --list --verbose }       # status of all distros
function wslip  { wsl -d kali-linux -- hostname -I }   # the distro's IP(s)

# --- drop into a distro at the *current* Windows directory --------------------
# `cdwsl` translates C:\path -> /mnt/c/path and starts a shell there.
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

