# ============================================================================
#  maint/Measure-Profile.ps1  -  standalone profile-load profiler / hang-finder
#
#  Why this exists: `prof-trace` routes timings through a child shell's console,
#  and if a fragment HANGS during load the child never prints anything — you just
#  see silence. This script instead times each fragment and appends a line to a
#  log file *immediately* (before AND after each fragment), so a hang leaves a
#  breadcrumb at the exact fragment that froze. It also never drops into psmux.
#
#  Run it (does NOT need your profile loaded):
#     pwsh -NoProfile -File "$HOME\dotfiles-Windows\maint\Measure-Profile.ps1"
#
#  If it finishes, it prints a slowest-first table at the end.
#  If it HANGS, open a second terminal and read the breadcrumb log:
#     Get-Content $env:TEMP\dotfiles-profile-timing.txt
#  The last line will be "START <layer>/<fragment>" with no matching time —
#  that's the fragment that hung. Tell me which one.
# ============================================================================

$ErrorActionPreference = 'Continue'
$env:PSMUX_NO_AUTOLAUNCH = '1'   # never drop into psmux mid-measure

# Minimal preamble so fragments don't trip on profile.ps1 globals they expect.
$root = if ($env:DOTFILES_WIN) { $env:DOTFILES_WIN } else { Join-Path $HOME 'dotfiles-Windows' }
$global:DOTFILES        = $root
$global:DotfilesTraceOn = $false                       # makes 10-tools' __lap a no-op
function global:Add-DotfilesTrace { param($Step, $Ms) }  # stub
$profileDir = Join-Path $root 'powershell'

$log = Join-Path $env:TEMP 'dotfiles-profile-timing.txt'
"profile timing  $(Get-Date -Format o)" | Set-Content -Path $log -Encoding utf8
"repo: $root"                            | Add-Content -Path $log -Encoding utf8

$results = [System.Collections.Generic.List[object]]::new()
$total = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($layer in @('core', 'os')) {
    $dir = Join-Path $profileDir $layer
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in (Get-ChildItem -Path $dir -Filter '*.ps1' | Sort-Object Name)) {
        $name = "$layer/$($f.Name)"
        # Breadcrumb BEFORE: if the next line never appears, this fragment hung.
        "START $name" | Add-Content -Path $log -Encoding utf8
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { . $f.FullName } catch { "   ERROR loading ${name}: $_" | Add-Content -Path $log -Encoding utf8 }
        $sw.Stop()
        $ms = [int]$sw.Elapsed.TotalMilliseconds
        ("  done {0,7} ms  {1}" -f $ms, $name) | Add-Content -Path $log -Encoding utf8
        $results.Add([pscustomobject]@{ Fragment = $name; ms = $ms })
    }
}

$total.Stop()
"" | Add-Content -Path $log -Encoding utf8
("TOTAL {0:N0} ms" -f $total.Elapsed.TotalMilliseconds) | Add-Content -Path $log -Encoding utf8
"" | Add-Content -Path $log -Encoding utf8
"slowest first:" | Add-Content -Path $log -Encoding utf8
($results | Sort-Object ms -Descending | Format-Table -AutoSize | Out-String -Width 200) |
    Add-Content -Path $log -Encoding utf8

# Print the whole log to this console (normal output stream — survives any host quirk).
Get-Content -Path $log
Write-Host "`n(also saved to $log)" -ForegroundColor DarkGray
