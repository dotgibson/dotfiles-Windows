# ============================================================================
#  packages/PackageLock.ps1  -  pure helpers for the package lockfile (B4).
#
#  The manifests (scoopfile.json / winget.json) are the DESIRED set and float to
#  latest. The lockfile (packages.lock.json) is the RESOLVED set: exact versions
#  captured from a real, working box, so `-Frozen` can reproduce that baseline
#  bit-for-bit — the same split npm/cargo use, and the same "reproducible at
#  install, current after maint" model packages/modules.ps1 already uses for PS
#  modules.
#
#  Everything here is PURE (string/JSON in, object out — no scoop/winget calls,
#  no disk writes), so it is unit-tested offline in tests/Packages.Tests.ps1.
#  Dot-sourced by Install-Packages.ps1 (the -Frozen consumer) and
#  Update-PackageLock.ps1 (the generator); side-effect-free on load.
# ============================================================================

# --- Read-PackageLock ---------------------------------------------------------
# Parse packages.lock.json text into { GeneratedAt; Scoop = @{name=ver}; Winget =
# @{id=ver} }. Tolerant by design: blank / malformed / partial JSON yields empty
# maps rather than throwing, so a missing or hand-corrupted lock degrades to "no
# pins" instead of breaking the installer. The maps are plain hashtables, so
# lookups are case-insensitive (scoop app names and winget ids both vary in case).
function Read-PackageLock {
    param([string]$Json)
    $empty = [pscustomobject]@{ GeneratedAt = $null; Scoop = @{}; Winget = @{} }
    if ([string]::IsNullOrWhiteSpace($Json)) { return $empty }
    try { $obj = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $empty }
    $toMap = {
        param($Section)
        $m = @{}
        if ($Section) {
            foreach ($p in $Section.PSObject.Properties) {
                if ($p.Value) { $m[$p.Name] = "$($p.Value)" }
            }
        }
        $m
    }
    [pscustomobject]@{
        GeneratedAt = $obj.generatedAt
        Scoop       = & $toMap $obj.scoop
        Winget      = & $toMap $obj.winget
    }
}

# --- Get-LockedVersion --------------------------------------------------------
# Case-insensitive lookup of one name in a lock map; $null when absent. (Hashtable
# indexing is already case-insensitive, but this keeps call sites readable and
# guards a $null map.)
function Get-LockedVersion {
    param([hashtable]$Map, [string]$Name)
    if (-not $Map -or [string]::IsNullOrEmpty($Name)) { return $null }
    if ($Map.ContainsKey($Name)) { return "$($Map[$Name])" }
    $null
}

# --- ConvertFrom-ScoopExport --------------------------------------------------
# `scoop export` (JSON) -> @{ appName = version }. Newer scoop emits
# { apps: [ { Name, Version, Source } ], buckets: [...] }; older scoop emitted a
# bare array of app objects. Accept both, keep only entries that actually carry a
# version (an app mid-install can lack one).
function ConvertFrom-ScoopExport {
    param([string]$Json)
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Json)) { return $map }
    try { $obj = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $map }
    $apps = if ($null -ne $obj.apps) { $obj.apps } else { $obj }
    foreach ($a in @($apps)) {
        if ($a.Name -and $a.Version) { $map["$($a.Name)"] = "$($a.Version)" }
    }
    $map
}

# --- ConvertFrom-WingetExport -------------------------------------------------
# `winget export --include-versions` (JSON) -> @{ id = version }. Shape is
# { Sources: [ { Packages: [ { PackageIdentifier, Version } ] } ] }. Skip entries
# with no usable version ("", "Unknown", "Latest") — winget without
# --include-versions omits versions entirely, and we must not pin to a non-version.
function ConvertFrom-WingetExport {
    param([string]$Json)
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Json)) { return $map }
    try { $obj = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $map }
    foreach ($s in @($obj.Sources)) {
        foreach ($p in @($s.Packages)) {
            $v = "$($p.Version)"
            if ($p.PackageIdentifier -and $v -and $v -notin 'Unknown', 'Latest') {
                $map["$($p.PackageIdentifier)"] = $v
            }
        }
    }
    $map
}

# --- Get-PackageLockDrift -----------------------------------------------------
# Compare the DESIRED names (from a manifest) against a lock map and report what's
# out of sync: Missing = desired-but-unlocked (added to the manifest without
# re-running the generator), Orphan = locked-but-no-longer-desired (removed from
# the manifest). This is the offline, CI-checkable half of B4 — it can't verify
# the version strings are the truly-installed ones, but it guarantees the lock and
# the manifest describe the SAME set. Case-insensitive.
function Get-PackageLockDrift {
    param([string[]]$DesiredNames, [hashtable]$LockMap)
    $desired = @($DesiredNames | Where-Object { $_ })
    $locked = @(if ($LockMap) { $LockMap.Keys })
    $missing = @($desired | Where-Object { $locked -notcontains $_ } | Sort-Object -Unique)
    $orphan = @($locked  | Where-Object { $desired -notcontains $_ } | Sort-Object -Unique)
    [pscustomobject]@{
        Missing = $missing
        Orphan  = $orphan
        InSync  = ($missing.Count -eq 0 -and $orphan.Count -eq 0)
    }
}

# --- New-PackageLockObject ----------------------------------------------------
# Assemble the lockfile object from resolved maps, ready for ConvertTo-Json. Keys
# are sorted so the committed file has a stable, diff-friendly order regardless of
# scoop/winget enumeration order. GeneratedAt is injected (not read from the clock)
# so the builder stays pure and testable.
function New-PackageLockObject {
    param([hashtable]$Scoop, [hashtable]$Winget, [string]$GeneratedAt)
    $sorted = {
        param($Map)
        $o = [ordered]@{}
        foreach ($k in @($Map.Keys | Sort-Object)) { $o[$k] = "$($Map[$k])" }
        $o
    }
    [ordered]@{
        _comment    = 'Generated by Update-PackageLock.ps1 - exact resolved versions for -Frozen installs. Do not hand-edit; re-run the generator.'
        generatedAt = $GeneratedAt
        scoop       = & $sorted $Scoop
        winget      = & $sorted $Winget
    }
}
