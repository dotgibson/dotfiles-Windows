# ============================================================================
#  Doctor.Helpers.ps1  -  pure dotfiles-doctor logic, owned by the Dotfiles
#  module (B7 stage 2b).
#
#  Extracted from os/45-doctor.ps1 so the host-INDEPENDENT pieces — the result
#  model, aggregation, the group classifier, the fragment-health mapper, the two
#  one-line detail formatters, and the remediation planner — live in the module
#  (exported, unit-tested in tests/Doctor.Tests.ps1) instead of as global:
#  functions. The host-SPECIFIC probes, the renderer, and the `dotfiles-doctor`
#  verb stay in the fragment and call these via the module export.
# ============================================================================

# --- result model -------------------------------------------------------------
function New-DoctorResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ok', 'warn', 'fail')][string]$Status,
        [string]$Detail = '',
        [string]$Hint   = ''
    )
    [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; Hint = $Hint }
}

# --- aggregate a set of results into counts + an overall verdict --------------
function Get-DoctorSummary {
    param([object[]]$Results)
    $ok   = @($Results | Where-Object Status -eq 'ok').Count
    $warn = @($Results | Where-Object Status -eq 'warn').Count
    $fail = @($Results | Where-Object Status -eq 'fail').Count
    $overall = if ($fail) { 'fail' } elseif ($warn) { 'warn' } else { 'ok' }
    [pscustomobject]@{ Ok = $ok; Warn = $warn; Fail = $fail; Total = $Results.Count; Overall = $overall }
}

# --- pure group classifier ----------------------------------------------------
# Bucket a result into a display section from its Name so the report reads as
# scannable groups instead of one flat list (U4). Pure, so it's unit-tested; the
# renderer just walks the fixed group order. Anything unmatched lands in 'Other',
# so a newly-added probe still shows up (merely ungrouped) instead of silently
# vanishing from the report.
function Get-DoctorGroup {
    [OutputType([string])]
    param([string]$Name)
    switch -Regex ($Name) {
        '^(PowerShell|Execution policy|Symlink)'                      { return 'Shell & environment' }
        '^(Repo|Profile link|link:|Modules|git identity|nvim vendor)' { return 'Repo & links' }
        '^(Profile fragments|Core toolchain)'                         { return 'Health & toolchain' }
        default                                                       { return 'Other' }
    }
}

# --- fragment-load health (pure: maps the loader's error list to a result) ----
# $null  -> profile never loaded (probably a direct dot-source, not a real shell)
# empty  -> every fragment loaded clean
# items  -> at least one fragment threw; surface the count + the first failure.
function Get-FragmentHealthResult {
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
function Get-DotRepoVersionDetail {
    param([string]$Sha, [bool]$IsDirty, [string]$When)
    if (-not $Sha) { return 'unknown (no git metadata)' }
    $detail = $Sha
    if ($When)    { $detail += "  ($When)" }
    if ($IsDirty) { $detail += '  [dirty]' }
    return $detail
}

# --- pure nvim-vendor formatter -----------------------------------------------
# Render nvim/.core-ref (written by nvim-sync.ps1) into a one-line detail: the
# short Core commit the vendored nvim/ tree came from, plus the commit date when
# known. Pure (the file read lives in the probe), so the formatting is unit-tested.
function Get-NvimVendorDetail {
    [OutputType([string])]
    param([string]$Sha, [string]$When)
    if (-not $Sha) { return 'no vendor ref recorded (run nvim-sync.ps1)' }
    $short = if ($Sha.Length -ge 7) { $Sha.Substring(0, 7) } else { $Sha }
    $detail = "vendored from core@$short"
    if ($When -and $When -ne 'unknown') { $detail += "  ($When)" }
    return $detail
}

# --- pure remediation planner -------------------------------------------------
# Map the non-ok results to a DEDUPED, ordered list of fix actions dotfiles-doctor
# -Fix can run. Pure (no host calls), so the routing is unit-tested; the actions
# themselves live in Invoke-DoctorFix (host-side, in the fragment).
function Get-DoctorFixPlan {
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
