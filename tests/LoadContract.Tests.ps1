# ============================================================================
#  tests/LoadContract.Tests.ps1  -  the profile's fragment load-order contract.
#
#  Each core/os fragment declares a machine-checked header:
#      # provides: <public functions it defines>
#      # requires: <dotfiles-internal names it calls>
#  This suite keeps those honest against the code (B6) and — the real point —
#  asserts the load order is SOUND: every name a fragment requires is already
#  provided by the Dotfiles module or a strictly-earlier-loading fragment. A
#  reorder, rename, or a helper used before it's defined trips this gate instead
#  of only surfacing as a broken shell on a fresh box.
#
#  Load order mirrors profile.ps1: the module first, then core/* and os/* each
#  globbed in name order (core before os).
# ============================================================================

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent $PSScriptRoot

    function Get-FragAst([string]$Path) {
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    }
    # Parse a "# key: a, b" header line. Returns @{ Present = <bool>; Names = @(...) };
    # "(none)" is Present with an empty Names list. Inlined-style (no @() return) so the
    # empty case can't collapse to $null.
    function Read-Decl([string[]]$Lines, [string]$Key) {
        $line = $Lines | Where-Object { $_ -match "^#\s*$Key\s*:" } | Select-Object -First 1
        $names = [System.Collections.Generic.List[string]]::new()
        if ($line) {
            $val = ($line -replace "^#\s*$Key\s*:\s*", '').Trim()
            if ($val -and $val -ne '(none)') {
                foreach ($n in ($val -split ',')) { if ($n.Trim()) { $names.Add($n.Trim()) } }
            }
        }
        @{ Present = [bool]$line; Names = $names.ToArray() }
    }

    $moduleExports = (Import-PowerShellDataFile (Join-Path $RepoRoot 'powershell/Dotfiles/Dotfiles.psd1')).FunctionsToExport

    # Fragments in load order: core/* then os/*, each sorted by name.
    $files = @('powershell/core', 'powershell/os') | ForEach-Object {
        Get-ChildItem (Join-Path $RepoRoot $_) -Filter *.ps1 | Sort-Object Name
    }

    # Pass 1: what each fragment defines (public vs script-scoped).
    $defined = [ordered]@{}
    foreach ($f in $files) {
        $ast = Get-FragAst $f.FullName
        $fns = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        $pub = [System.Collections.Generic.List[string]]::new(); $int = @()
        foreach ($fn in $fns) {
            $n = $fn.Name -replace '^(global:|script:)', ''
            if ($fn.Name -match '^script:') { $int += $n }
            elseif (-not $pub.Contains($n)) { $pub.Add($n) }
        }
        $defined[$f.Name] = @{ Public = $pub.ToArray(); Internal = @($int) }
    }
    $universe = @($moduleExports + ($defined.Values | ForEach-Object { $_.Public + $_.Internal }) | Select-Object -Unique)

    # Pass 2: per-fragment case data (declared vs computed, providers-before).
    $providersBefore = [System.Collections.Generic.List[string]]::new()
    $providersBefore.AddRange([string[]]$moduleExports)
    $script:Cases = foreach ($f in $files) {
        $lines = Get-Content $f.FullName
        $ast = Get-FragAst $f.FullName
        $cmds = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        $refs = ($cmds | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }) |
            ForEach-Object { $_ -replace '^(global:|script:)', '' } | Select-Object -Unique
        $self = $defined[$f.Name].Public + $defined[$f.Name].Internal
        $computedReq = @($refs | Where-Object { $universe -contains $_ -and $self -notcontains $_ } | Sort-Object -Unique)

        $prov = Read-Decl $lines 'provides'
        $req = Read-Decl $lines 'requires'
        $case = @{
            Name            = $f.Name
            HasProvides     = $prov.Present
            HasRequires     = $req.Present
            DeclaredProv    = $prov.Names
            DeclaredReq     = $req.Names
            ActualPublic    = @($defined[$f.Name].Public)
            ComputedReq     = $computedReq
            ProvidersBefore = @($providersBefore.ToArray())
        }
        $providersBefore.AddRange([string[]]@($defined[$f.Name].Public))
        $providersBefore.AddRange([string[]]@($defined[$f.Name].Internal))
        $case
    }
}

Describe 'fragment load contract' {
    It '<Name> declares provides: and requires: header lines' -ForEach $script:Cases {
        $HasProvides | Should -BeTrue -Because "$Name should declare a '# provides:' line (use (none) if it defines no public verbs)"
        $HasRequires | Should -BeTrue -Because "$Name should declare a '# requires:' line (use (none) if it has no dotfiles deps)"
    }

    It '<Name> declares only real public functions in provides:' -ForEach $script:Cases {
        foreach ($p in $DeclaredProv) {
            $ActualPublic | Should -Contain $p -Because "$Name declares provide '$p' it doesn't define"
        }
    }

    It '<Name> requires: matches its actual dotfiles-internal dependencies' -ForEach $script:Cases {
        ($DeclaredReq | Sort-Object) | Should -Be ($ComputedReq | Sort-Object) `
            -Because "$Name's declared requires drifted from the code (update the header)"
    }

    It '<Name> only requires names provided by the module or an earlier fragment' -ForEach $script:Cases {
        foreach ($r in $ComputedReq) {
            $ProvidersBefore | Should -Contain $r `
                -Because "$Name uses '$r' before any earlier-loading source provides it"
        }
    }
}
