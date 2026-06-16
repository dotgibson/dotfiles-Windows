# ============================================================================
#  Wsl.Helpers.ps1  -  pure WSL path logic, owned by the Dotfiles module (B7).
#
#  Extracted from os/31-wsl-bridge.ps1 so the pure, host-independent translation
#  lives in the module (exported, unit-tested) instead of as a global: function.
#  The wsl-DEPENDENT command verbs (kali/debian/cdwsl/...) stay in the fragment,
#  behind its `Test-Cmd wsl` guard, and call this via the module export.
# ============================================================================

# --- ConvertTo-WslPath --------------------------------------------------------
# Translate a Windows path to its /mnt form: C:\Users\me -> /mnt/c/Users/me
# (drive lower-cased, backslashes normalized). Accepts forward- or back-slash
# separators; returns $null for anything that isn't a drive-letter path (UNC, or
# an already-translated /mnt path) so callers can fall back.
function ConvertTo-WslPath {
    [OutputType([string])]
    param([string]$Path)
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }
    return $null
}
