# ============================================================================
#  os/45-doctor.ps1  -  `dotfiles-doctor`: one command that audits whether this
#  host is wired up correctly, so a half-finished bootstrap stops being a silent
#  mystery. Every check reports ok / warn / fail with a concrete fix hint.
#
#      dotfiles-doctor            # human-readable report + summary line
#      dotfiles-doctor -Quiet     # just the summary
#      dotfiles-doctor -PassThru  # emit the result objects (for scripting/tests)
#
#  The probes are host-specific (registry, execution policy, symlinks, PATH), but
#  the result model, aggregation, and rendering are pure functions so they're
#  unit-tested (tests/Doctor.Tests.ps1).
# ============================================================================

# --- result model -------------------------------------------------------------
function global:New-DoctorResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ok', 'warn', 'fail')][string]$Status,
        [string]$Detail = '',
        [string]$Hint   = ''
    )
    [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; Hint = $Hint }
}

# --- aggregate a set of results into counts + an overall verdict --------------
function global:Get-DoctorSummary {
    param([object[]]$Results)
    $ok   = @($Results | Where-Object Status -eq 'ok').Count
    $warn = @($Results | Where-Object Status -eq 'warn').Count
    $fail = @($Results | Where-Object Status -eq 'fail').Count
    $overall = if ($fail) { 'fail' } elseif ($warn) { 'warn' } else { 'ok' }
    [pscustomobject]@{ Ok = $ok; Warn = $warn; Fail = $fail; Total = $Results.Count; Overall = $overall }
}

# --- render one result line ---------------------------------------------------
# Glyphs/colour route through the shared helpers (core/05-lib.ps1) so the report
# degrades cleanly under NO_COLOR / DOTFILES_ASCII like every other renderer.
function script:Write-DoctorLine {
    param([object]$Result)
    $glyph, $color = switch ($Result.Status) {
        'ok'   { (Get-DotGlyph ok),   'Green' }
        'warn' { (Get-DotGlyph warn), 'Yellow' }
        'fail' { (Get-DotGlyph fail), 'Red' }
    }
    Write-DotHost "  $glyph " -Color $color -NoNewline
    Write-Host ("{0,-26}" -f $Result.Name) -NoNewline
    Write-DotHost " $($Result.Detail)" -Color Gray
    if ($Result.Status -ne 'ok' -and $Result.Hint) {
        Write-DotHost ("      {0} {1}" -f (Get-DotGlyph arrow), $Result.Hint) -Color DarkGray
    }
}

# --- a symlink that resolves into the dotfiles repo? --------------------------
function script:Test-LinkIntoRepo {
    param([string]$Link)
    if (-not (Test-Path -LiteralPath $Link)) { return $false }
    $item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.LinkType -ne 'SymbolicLink') { return $false }
    $target = @($item.Target)[0]
    return ($target -and $global:DOTFILES -and $target -like "*$($global:DOTFILES)*")
}

# --- fragment-load health (pure: maps the loader's error list to a result) ----
# $null  -> profile never loaded (probably a direct dot-source, not a real shell)
# empty  -> every fragment loaded clean
# items  -> at least one fragment threw; surface the count + the first failure.
function global:Get-FragmentHealthResult {
    param($LoadErrors)
    if ($null -eq $LoadErrors) {
        return New-DoctorResult 'Profile fragments' 'warn' 'not loaded via the profile' 'open a new pwsh shell so the profile loads'
    }
    $list = @($LoadErrors)
    if ($list.Count -eq 0) {
        return New-DoctorResult 'Profile fragments' 'ok' 'all fragments loaded clean'
    }
    return New-DoctorResult 'Profile fragments' 'fail' "$($list.Count) failed: $($list[0])" 'fix the fragment, then run: reload'
}

# --- the probes (host-specific; each returns a DoctorResult) ------------------
function script:Get-DoctorResults {
    $r = [System.Collections.Generic.List[object]]::new()

    # pwsh edition
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $r.Add((New-DoctorResult 'PowerShell 7 (pwsh)' 'ok' "v$($PSVersionTable.PSVersion)"))
    } else {
        $r.Add((New-DoctorResult 'PowerShell 7 (pwsh)' 'warn' 'running Windows PowerShell 5.1' 'do daily work in pwsh — the profile targets it'))
    }

    # execution policy (CurrentUser)
    try {
        $pol = Get-ExecutionPolicy -Scope CurrentUser
        if ($pol -in 'RemoteSigned', 'Unrestricted', 'Bypass') {
            $r.Add((New-DoctorResult 'Execution policy' 'ok' "$pol (CurrentUser)"))
        } else {
            $r.Add((New-DoctorResult 'Execution policy' 'fail' "$pol blocks the profile" 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'))
        }
    } catch { $r.Add((New-DoctorResult 'Execution policy' 'warn' 'could not read (Group Policy?)' '')) }

    # symlink capability
    $devMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (($devMode -eq 1) -or $isAdmin) {
        $r.Add((New-DoctorResult 'Symlink capability' 'ok' $(if ($isAdmin) { 'elevated' } else { 'Developer Mode on' })))
    } else {
        $r.Add((New-DoctorResult 'Symlink capability' 'warn' 'no Dev Mode / not elevated' 'enable Developer Mode so install.ps1 links instead of copies'))
    }

    # Repo root: the profile sets $global:DOTFILES from $env:DOTFILES_WIN, but
    # accept either so a direct dot-source (no profile) still reports accurately.
    $root = if ($global:DOTFILES) { $global:DOTFILES } else { $env:DOTFILES_WIN }
    if ($root -and (Test-Path $root)) {
        $r.Add((New-DoctorResult 'Repo root' 'ok' $root))
    } else {
        $r.Add((New-DoctorResult 'Repo root' 'fail' 'DOTFILES_WIN unset/missing' 're-run install.ps1 to set DOTFILES_WIN'))
    }

    # profile symlink
    if (Test-LinkIntoRepo $PROFILE) {
        $r.Add((New-DoctorResult 'Profile link' 'ok' 'symlinked into the repo'))
    } elseif (Test-Path $PROFILE) {
        $r.Add((New-DoctorResult 'Profile link' 'warn' 'exists but not a repo symlink' 're-run install.ps1 -SkipPackages'))
    } else {
        $r.Add((New-DoctorResult 'Profile link' 'fail' 'no $PROFILE' 'run install.ps1'))
    }

    # modules off OneDrive
    $localModules = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
    if ($env:PSModulePath -like "*$localModules*") {
        $r.Add((New-DoctorResult 'Modules off OneDrive' 'ok' 'local module path is on PSModulePath'))
    } else {
        $r.Add((New-DoctorResult 'Modules off OneDrive' 'warn' 'local module path not prepended' 'open a new shell; run modules-localize once'))
    }

    # key config links
    $links = @{
        '.gitconfig'      = (Join-Path $HOME '.gitconfig')
        'nvim config'     = (Join-Path $env:LOCALAPPDATA 'nvim')
        'psmux.conf'      = (Join-Path $HOME '.config\psmux\psmux.conf')
        'ssh config'      = (Join-Path $HOME '.ssh\config')
    }
    foreach ($name in $links.Keys) {
        if (Test-LinkIntoRepo $links[$name]) { $r.Add((New-DoctorResult "link: $name" 'ok' 'linked')) }
        elseif (Test-Path $links[$name])     { $r.Add((New-DoctorResult "link: $name" 'warn' 'present, not a repo link' 're-run install.ps1 -SkipPackages')) }
        else                                  { $r.Add((New-DoctorResult "link: $name" 'warn' 'missing' 'run install.ps1')) }
    }

    # gitconfig.local identity
    $gcLocal = Join-Path $HOME '.gitconfig.local'
    if ((Test-Path $gcLocal) -and ((Get-Content $gcLocal -Raw) -notmatch 'YOUR NAME|you@example\.com')) {
        $r.Add((New-DoctorResult 'git identity' 'ok' 'name/email set in ~/.gitconfig.local'))
    } else {
        $r.Add((New-DoctorResult 'git identity' 'warn' 'placeholder or missing' 'set your name/email in ~/.gitconfig.local'))
    }

    # profile fragment load health (B7): the loader records any fragment that
    # threw into $global:DotfilesLoadErrors. Classification is pure (unit-tested).
    $r.Add((Get-FragmentHealthResult $global:DotfilesLoadErrors))

    # core toolchain on PATH
    $core = 'git', 'starship', 'zoxide', 'fzf', 'rg', 'fd', 'bat', 'eza', 'nvim', 'psmux'
    $missing = $core | Where-Object { -not (Test-Cmd $_) }
    if (-not $missing) {
        $r.Add((New-DoctorResult 'Core toolchain' 'ok' "$($core.Count) tools present"))
    } else {
        $r.Add((New-DoctorResult 'Core toolchain' 'warn' "missing: $($missing -join ', ')" 're-run .\packages\Install-Packages.ps1'))
    }

    return $r
}

function global:dotfiles-doctor {
    [CmdletBinding()]
    param([switch]$Quiet, [switch]$PassThru)

    $results = Get-DoctorResults
    if (-not $Quiet) {
        Write-Host ''
        if (Test-DotColor) {
            Write-Host ' dotfiles-doctor ' -ForegroundColor Black -BackgroundColor Cyan
        } else {
            Write-Host '== dotfiles-doctor =='
        }
        Write-Host ''
        foreach ($res in $results) { Write-DoctorLine $res }
        Write-Host ''
    }

    $s = Get-DoctorSummary $results
    $color = switch ($s.Overall) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'fail' { 'Red' } }
    $sep = if (Test-DotUnicode) { '·' } else { '|' }
    Write-DotHost ("  {0} ok {3} {1} warn {3} {2} fail" -f $s.Ok, $s.Warn, $s.Fail, $sep) -Color $color

    if ($PassThru) { return $results }
}
