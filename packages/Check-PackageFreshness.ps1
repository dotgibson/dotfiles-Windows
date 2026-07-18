#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
  Report managed scoop/winget apps whose upstream version is ahead of packages.lock.json.

.DESCRIPTION
  FINDINGS ONLY — this never edits the lock. Re-pinning requires the apps actually
  installed (run Update-PackageLock.ps1 on your box), so this just flags what is behind.
  Built to run on a windows-latest runner via .github/workflows/package-freshness.yml,
  where scoop + winget resolve real versions. Writes a markdown report to -ReportPath
  when anything is behind; removes the file and exits 0 when everything matches.

  Reuses Read-PackageLock / Get-LockedVersion from packages/PackageLock.ps1 so it reads
  the lock exactly as the rest of the package tooling does. Per-app failures are warned
  and skipped — a single unresolvable package never fails the run.
#>
[CmdletBinding()]
param(
    [string]$ReportPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'package-freshness.md'),
    [switch]$SkipScoop,
    [switch]$SkipWinget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath
. (Join-Path $here 'PackageLock.ps1')

$lock       = Read-PackageLock (Get-Content (Join-Path $here 'packages.lock.json') -Raw)
$scoopfile  = Get-Content (Join-Path $here 'scoopfile.json') -Raw | ConvertFrom-Json
$wingetfile = Get-Content (Join-Path $here 'winget.json')   -Raw | ConvertFrom-Json

$outdated = [System.Collections.Generic.List[object]]::new()
$skipped  = [System.Collections.Generic.List[string]]::new()

function Test-ExactVersion {
    # An exact pin we can compare; ranges/constraints like "> 8.12" are skipped.
    param([string]$Value)
    return $Value -match '^[0-9][0-9A-Za-z._+-]*$'
}

# ---- scoop: install (no apps) + add buckets, then read manifest versions off disk ----
if (-not $SkipScoop) {
    try {
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            # Fetch the installer to a STRING first so it can be integrity-checked
            # before it runs — the same opt-in gate install.ps1 applies, so ONE
            # DOTFILES_SCOOP_SHA256 value covers both the installer and this CI path
            # (that gap — CI had no gate — is what issue #129 flagged). The SHA is
            # computed over the UTF-8 string bytes exactly as install.ps1's
            # Get-DotStringSha256 does, so the same expected hash matches here.
            # Deliberately NO hardcoded pin: get.scoop.sh is a moving target, so a
            # baked-in SHA would break CI on every upstream installer edit.
            $scoopSrc = Invoke-RestMethod -Uri 'https://get.scoop.sh'
            # Hash and WRITE the exact same UTF-8 byte array, so the file that runs is
            # byte-for-byte what we verified (Set-Content re-encodes / appends a newline,
            # so it would NOT match the hashed bytes). These bytes are the BOM-less UTF-8
            # of the string — GetBytes never emits a preamble — matching install.ps1's
            # Get-DotStringSha256, so one DOTFILES_SCOOP_SHA256 value covers both paths.
            $scoopBytes = [System.Text.Encoding]::UTF8.GetBytes($scoopSrc)
            if ($env:DOTFILES_SCOOP_SHA256) {
                $sha = [System.Security.Cryptography.SHA256]::Create()
                try { $actual = (($sha.ComputeHash($scoopBytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
                finally { $sha.Dispose() }
                if ($actual -ne $env:DOTFILES_SCOOP_SHA256.ToLowerInvariant()) {
                    # A mismatched installer is a security STOP, not a transient setup
                    # hiccup — throw a tagged error the outer catch re-raises (below) so
                    # the run actually fails instead of warning and carrying on.
                    throw "scoop installer hash mismatch — expected $($env:DOTFILES_SCOOP_SHA256), got $actual"
                }
            }
            # Must run as a FILE (scoop's installer takes -RunAsAdmin, which iex can't
            # pass). WriteAllBytes emits exactly the verified bytes — no re-encoding.
            $installer = Join-Path ([System.IO.Path]::GetTempPath()) 'install-scoop.ps1'
            [System.IO.File]::WriteAllBytes($installer, $scoopBytes)
            & $installer -RunAsAdmin 2>&1 | Out-Null   # CI runs elevated; -RunAsAdmin lets scoop install anyway
            $env:PATH = "$HOME\scoop\shims;$env:PATH"   # make `scoop` resolvable in this session
        }
        foreach ($b in $scoopfile.buckets) {
            try { scoop bucket add $b.Name $b.Source 2>&1 | Out-Null } catch { }
        }
    } catch {
        # A tampered-installer hash mismatch must fail the run, not degrade to a
        # warning — re-throw it. Transient setup failures (network, bucket add) stay
        # tolerant so a single flaky source never fails the freshness check.
        if ($_.Exception.Message -like 'scoop installer hash mismatch*') { throw }
        Write-Warning "scoop setup failed: $($_.Exception.Message)"
    }

    $bucketRoot = Join-Path $HOME 'scoop\buckets'
    foreach ($app in $scoopfile.apps) {
        $name   = $app.Name
        $bucket = $app.Source
        $locked = Get-LockedVersion $lock.Scoop $name
        if (-not $locked) { continue }
        if (-not (Test-ExactVersion $locked)) { $skipped.Add("scoop/$name (lock '$locked' is not an exact pin)"); continue }
        $avail = $null
        try {
            $manifest = Get-ChildItem -Path (Join-Path $bucketRoot $bucket) -Recurse -Filter "$name.json" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($manifest) { $avail = (Get-Content $manifest.FullName -Raw | ConvertFrom-Json).version }
        } catch { $avail = $null }
        if (-not $avail) { $skipped.Add("scoop/$name (no manifest version in bucket '$bucket')"); continue }
        if ("$avail" -ne "$locked") {
            $outdated.Add([pscustomobject]@{ Manager = 'scoop'; Name = $name; Locked = $locked; Available = "$avail" })
        }
    }
}

# ---- winget: ask the live source for the latest version of each managed id ----
if (-not $SkipWinget) {
    foreach ($entry in $wingetfile.packages) {
        $id = if ($entry -is [string]) { $entry }
              elseif ($entry.PSObject.Properties.Name -contains 'id') { $entry.id }
              else { $null }
        if (-not $id) { continue }
        $locked = Get-LockedVersion $lock.Winget $id
        if (-not $locked) { continue }
        if (-not (Test-ExactVersion $locked)) { $skipped.Add("winget/$id (lock '$locked' is not an exact pin)"); continue }
        $avail = $null
        try {
            $out = (winget show --id $id --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
            $m = [regex]::Match($out, '(?im)^\s*Version:\s*(.+?)\s*$')
            if ($m.Success) { $avail = $m.Groups[1].Value.Trim() }
        } catch { $avail = $null }
        if (-not $avail) { $skipped.Add("winget/$id (version not resolved)"); continue }
        if ($avail -ne $locked) {
            $outdated.Add([pscustomobject]@{ Manager = 'winget'; Name = $id; Locked = $locked; Available = $avail })
        }
    }
}

# ---- report ----
if (Test-Path $ReportPath) { Remove-Item $ReportPath -Force }

if ($outdated.Count -eq 0) {
    Write-Output "All managed scoop/winget packages match packages.lock.json ($($skipped.Count) skipped)."
    exit 0
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('The following managed packages are behind their upstream version (vs `packages.lock.json`):')
$lines.Add('')
$lines.Add('| Manager | Package | Locked | Available |')
$lines.Add('| --- | --- | --- | --- |')
foreach ($o in ($outdated | Sort-Object Manager, Name)) {
    $lines.Add("| $($o.Manager) | ``$($o.Name)`` | $($o.Locked) | $($o.Available) |")
}
$lines.Add('')
$lines.Add('Re-pin from a box with the apps installed: `.\packages\Update-PackageLock.ps1`, then commit `packages.lock.json`.')
if ($skipped.Count -gt 0) {
    $lines.Add('')
    $lines.Add('<details><summary>Skipped (could not compare)</summary>')
    $lines.Add('')
    foreach ($s in $skipped) { $lines.Add("- $s") }
    $lines.Add('')
    $lines.Add('</details>')
}
Set-Content -Path $ReportPath -Value ($lines -join "`n") -Encoding UTF8
Write-Output "$($outdated.Count) package(s) behind upstream — report written to $ReportPath"
exit 0
