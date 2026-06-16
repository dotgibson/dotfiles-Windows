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

# --- pure provenance formatter ------------------------------------------------
# Render the repo's git state into a one-line detail: short SHA, a (dirty) marker
# when there are uncommitted changes, and the commit date when known. Pure (the
# git calls live in the probe), so the formatting is unit-tested.
function global:Get-DotRepoVersionDetail {
    param([string]$Sha, [bool]$IsDirty, [string]$When)
    if (-not $Sha) { return 'unknown (no git metadata)' }
    $detail = $Sha
    if ($When)    { $detail += "  ($When)" }
    if ($IsDirty) { $detail += '  [dirty]' }
    return $detail
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

    # Repo provenance: which revision is actually on this box (and is it dirty?).
    # Informational — a copy-install with no .git is fine, just unversioned.
    if ($root -and (Test-Path (Join-Path $root '.git')) -and (Test-Cmd git)) {
        $sha   = (& git -C $root rev-parse --short HEAD 2>$null)
        $when  = (& git -C $root show -s --format=%cs HEAD 2>$null)
        $dirty = [bool]((& git -C $root status --porcelain 2>$null) | Select-Object -First 1)
        $r.Add((New-DoctorResult 'Repo version' 'ok' (Get-DotRepoVersionDetail -Sha "$sha" -IsDirty $dirty -When "$when")))
    } else {
        $r.Add((New-DoctorResult 'Repo version' 'ok' 'not a git checkout (copy install — unversioned)'))
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

    # key config links — enumerated from the SAME shared plan install.ps1 wires
    # and uninstall.ps1 removes (Get-DotfilesLinkPlan), so doctor can't fall out of
    # sync with the actual link set. The profile link is checked separately above,
    # so it's skipped here to avoid a duplicate row.
    if ($root) {
        foreach ($row in (Get-DotfilesLinkPlan -RepoRoot $root)) {
            if ($row.Name -eq 'PowerShell profile') { continue }
            if (Test-LinkIntoRepo $row.Link)  { $r.Add((New-DoctorResult "link: $($row.Name)" 'ok' 'linked')) }
            elseif (Test-Path $row.Link)      { $r.Add((New-DoctorResult "link: $($row.Name)" 'warn' 'present, not a repo link' 're-run install.ps1 -SkipPackages')) }
            else                              { $r.Add((New-DoctorResult "link: $($row.Name)" 'warn' 'missing' 'run install.ps1')) }
        }
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

# --- pure remediation planner -------------------------------------------------
# Map the non-ok results to a DEDUPED, ordered list of fix actions dotfiles-doctor
# -Fix can run. Pure (no host calls), so the routing is unit-tested; the actions
# themselves live in Invoke-DoctorFix below.
function global:Get-DoctorFixPlan {
    param([object[]]$Results)
    $plan = [System.Collections.Generic.List[string]]::new()
    $add  = { param($k) if ($plan -notcontains $k) { $plan.Add($k) } }
    foreach ($res in $Results) {
        if ($res.Status -eq 'ok') { continue }
        switch -Regex ($res.Name) {
            '^Execution policy$'     { & $add 'execpolicy' }
            '^Profile link$'         { & $add 'rewire' }
            '^link: '                { & $add 'rewire' }
            '^Modules off OneDrive$' { & $add 'localize-modules' }
            '^Core toolchain$'       { & $add 'install-packages' }
        }
    }
    return $plan
}

# Run one planned action. Side-effecting (host), so it's kept tiny and out of the
# pure planner. Unknown keys are a no-op.
function script:Invoke-DoctorFix {
    param([string]$Key)
    switch ($Key) {
        'execpolicy' {
            Write-DotHost '  → setting CurrentUser execution policy to RemoteSigned' -Color Cyan
            try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch { Write-DotErr "failed: $_" }
        }
        'rewire' {
            $install = Join-Path $global:DOTFILES 'install.ps1'
            if (Test-Path $install) {
                Write-DotHost '  → re-wiring config symlinks (install.ps1 -SkipPackages)' -Color Cyan
                & $install -SkipPackages -NonInteractive
            } else { Write-DotErr 'install.ps1 not found' 'set DOTFILES_WIN / re-clone the repo' }
        }
        'localize-modules' {
            if (Get-Command modules-localize -ErrorAction SilentlyContinue) {
                Write-DotHost '  → moving modules off OneDrive (modules-localize)' -Color Cyan
                modules-localize
            } else { Write-DotErr 'modules-localize not available' 'open a new pwsh shell, then run it' }
        }
        'install-packages' {
            Write-DotWarn 'missing tools need the package installer.' 'run: .\packages\Install-Packages.ps1'
        }
    }
}

function global:dotfiles-doctor {
    [CmdletBinding()]
    param([switch]$Quiet, [switch]$PassThru, [switch]$Fix)

    $results = Get-DoctorResults
    if (-not $Quiet) {
        Write-Host ''
        Write-DotBanner 'dotfiles-doctor'
        Write-Host ''
        foreach ($res in $results) { Write-DoctorLine $res }
        Write-Host ''
    }

    $s = Get-DoctorSummary $results
    $color = switch ($s.Overall) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'fail' { 'Red' } }
    $sep = if (Test-DotUnicode) { '·' } else { '|' }
    Write-DotHost ("  {0} ok {3} {1} warn {3} {2} fail" -f $s.Ok, $s.Warn, $s.Fail, $sep) -Color $color

    # Opt-in remediation: only acts on the checks it knows how to fix, and says
    # exactly what it's doing for each. Re-runs the probes afterward so you see
    # the result without another command.
    if ($Fix) {
        $plan = Get-DoctorFixPlan $results
        Write-Host ''
        if (-not $plan.Count) {
            Write-DotHost '  nothing auto-fixable here.' -Color DarkGray
        } else {
            Write-DotHost ("  applying {0} fix(es)..." -f $plan.Count) -Color Cyan
            foreach ($key in $plan) { Invoke-DoctorFix $key }
            Write-Host ''
            Write-DotHost '  re-checking...' -Color Cyan
            $results = Get-DoctorResults
            $s = Get-DoctorSummary $results
            $color = switch ($s.Overall) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'fail' { 'Red' } }
            Write-DotHost ("  {0} ok {3} {1} warn {3} {2} fail" -f $s.Ok, $s.Warn, $s.Fail, $sep) -Color $color
        }
    }

    if ($PassThru) { return $results }
}
