# ============================================================================
#  tests/Repo.Tests.ps1  -  Pester v5 suite (runs in CI on a Windows runner).
#
#  Structural/regression gates that don't need a live Windows host:
#    • every *.ps1 parses with no syntax errors
#    • package manifests are valid and free of duplicates
#    • the .gitconfig has the expected include for the gitignored local identity
#  Behavioral gates for individual fixes live next to them (e.g. Lib.Tests.ps1).
#
#  Local quick gate (no Pester/Gallery needed): tests/Invoke-Validation.ps1
# ============================================================================

BeforeDiscovery {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Ps1Files = Get-ChildItem -Path $script:RepoRoot -Recurse -Filter *.ps1 -File |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
}

Describe 'PowerShell syntax' {
    It '<RelPath> parses with no errors' -ForEach (
        $script:Ps1Files | ForEach-Object {
            @{ Path = $_.FullName; RelPath = $_.FullName.Substring($script:RepoRoot.Length + 1) }
        }
    ) {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}

Describe 'Package manifests' {
    BeforeAll { $RepoRoot = Split-Path -Parent $PSScriptRoot }

    It 'scoopfile.json is valid JSON with apps and buckets' {
        $m = Get-Content (Join-Path $RepoRoot 'packages/scoopfile.json') -Raw | ConvertFrom-Json
        $m.apps    | Should -Not -BeNullOrEmpty
        $m.buckets | Should -Not -BeNullOrEmpty
    }
    It 'scoopfile.json has no duplicate apps' {
        $m = Get-Content (Join-Path $RepoRoot 'packages/scoopfile.json') -Raw | ConvertFrom-Json
        ($m.apps.Name | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }
    It 'scoopfile.json references only declared buckets' {
        $m = Get-Content (Join-Path $RepoRoot 'packages/scoopfile.json') -Raw | ConvertFrom-Json
        $declared = $m.buckets.Name
        foreach ($app in $m.apps) { $declared | Should -Contain $app.Source }
    }
    It 'winget.json is valid JSON with no duplicate ids' {
        $w = (Get-Content (Join-Path $RepoRoot 'packages/winget.json') -Raw | ConvertFrom-Json).packages
        $w | Should -Not -BeNullOrEmpty
        # Entries may be a bare id string OR an object { id, version, group } (U3) —
        # normalize to ids before the duplicate check.
        $ids = foreach ($e in $w) { if ($e -is [string]) { $e } else { $e.id } }
        ($ids | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }
    It 'every winget id is a Publisher.Package form (provenance)' {
        $w = (Get-Content (Join-Path $RepoRoot 'packages/winget.json') -Raw | ConvertFrom-Json).packages
        $ids = foreach ($e in $w) { if ($e -is [string]) { $e } else { $e.id } }
        foreach ($id in $ids) { $id | Should -Match '^[^\s.]+(\.[^\s.]+)+$' }
    }
    It 'every scoop app has a plausible id (provenance)' {
        $m = Get-Content (Join-Path $RepoRoot 'packages/scoopfile.json') -Raw | ConvertFrom-Json
        foreach ($app in $m.apps) { $app.Name | Should -Match '^[\w.+-]+$' }
    }
}

Describe 'Managed module pins' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $RepoRoot 'packages/modules.ps1')
    }
    It 'pins a version floor for every managed module' {
        $script:MaintModulePins.Count | Should -BeGreaterThan 0
        foreach ($name in $script:MaintModulePins.Keys) {
            $script:MaintModulePins[$name] | Should -Match '^\d+\.\d+'
        }
    }
    It 'keeps the name list in sync with the pins' {
        @($script:MaintModuleNames).Count | Should -Be $script:MaintModulePins.Count
    }
}

Describe 'repo hygiene' {
    BeforeAll { $RepoRoot = Split-Path -Parent $PSScriptRoot }
    It 'ships an .editorconfig' {
        Test-Path (Join-Path $RepoRoot '.editorconfig') | Should -BeTrue
    }
    It 'install.ps1 excludes the .git tree from Unblock-File' {
        $i = Get-Content (Join-Path $RepoRoot 'install.ps1') -Raw
        $i | Should -Match "notlike '\*\\\.git\\\*'"
    }
    It 'Maintenance.ps1 has no garbled nested-hash comment' {
        $m = Get-Content (Join-Path $RepoRoot 'maint/Maintenance.ps1') -Raw
        $m | Should -Not -Match '#\s+#\s+#'
    }
    It '<RelPath> ends with a final newline (editorconfig)' -ForEach (
        $script:Ps1Files | ForEach-Object {
            @{ Path = $_.FullName; RelPath = $_.FullName.Substring($script:RepoRoot.Length + 1) }
        }
    ) {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length) { $bytes[-1] | Should -Be 0x0A }
    }
}

Describe 'README layout box tracks the actual fragments (B15)' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        $readme = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
        # Grab the fenced code block under "## Layout" (allow an optional language/
        # info string after the opening fence, e.g. ```text).
        $m = [regex]::Match($readme, '(?ms)^## Layout\s*\r?\n```[^\r\n]*\r?\n(.*?)\r?\n```')
        $script:LayoutBlock = if ($m.Success) { $m.Groups[1].Value } else { '' }
        # Fragment tokens in the box (NN-name), e.g. 05-lib, 31-wsl-bridge, 57-health-nudge.
        $script:DocFrags = [regex]::Matches($script:LayoutBlock, '\b\d{2}-[a-z][a-z-]*') |
            ForEach-Object { $_.Value } | Sort-Object -Unique
        # Actual fragments on disk (core + os), basename without .ps1.
        $script:DiskFrags = Get-ChildItem `
            (Join-Path $RepoRoot 'powershell/core'), (Join-Path $RepoRoot 'powershell/os') -Filter *.ps1 |
            ForEach-Object { $_.BaseName } | Sort-Object -Unique
    }
    It 'finds the Layout code block' {
        $script:LayoutBlock | Should -Not -BeNullOrEmpty
    }
    It 'lists exactly the on-disk core/os fragments (no missing, no stale)' {
        # Equal sets: a new fragment must be added to the box, a removed one dropped.
        ($script:DocFrags -join ', ') | Should -Be ($script:DiskFrags -join ', ') `
            -Because 'the README Layout box drifted from powershell/core + powershell/os (update it)'
    }
}

Describe 'psmux config' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:Conf = Get-Content (Join-Path $RepoRoot 'psmux/psmux.conf') -Raw
    }
    It 'reads the status pill via an explicit cmd /c (not the pwsh type alias)' {
        # In the pwsh default-shell, `type` aliases Get-Content and %VAR% does not
        # expand; the pill segment must go through cmd /c to render at all.
        $script:Conf | Should -Match '#\(cmd /c type %LOCALAPPDATA%'
    }
    It 'silences the missing-cache error so the segment renders nothing when off' {
        $script:Conf | Should -Match 'psmux-netinfo\.pill 2>NUL'
    }
}

Describe 'git config' {
    BeforeAll { $RepoRoot = Split-Path -Parent $PSScriptRoot }
    It 'includes the gitignored local identity file' {
        $gc = Get-Content (Join-Path $RepoRoot 'git/.gitconfig') -Raw
        $gc | Should -Match 'path\s*=\s*~/\.gitconfig\.local'
    }
    It 'gitignores the local identity and profile override' {
        $gi = Get-Content (Join-Path $RepoRoot '.gitignore') -Raw
        $gi | Should -Match '\.gitconfig\.local'
        $gi | Should -Match 'powershell/local\.ps1'
    }
}

Describe 'dev-dependency pins match CI' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        $env:DOTFILES_DEVDEPS_LIBONLY = '1'
        . (Join-Path $RepoRoot 'tests/Install-DevDeps.ps1')
        $script:Ci = Get-Content (Join-Path $RepoRoot '.github/workflows/ci.yml') -Raw
    }
    AfterAll { Remove-Item Env:DOTFILES_DEVDEPS_LIBONLY -ErrorAction SilentlyContinue }
    It 'pins Pester to the CI PESTER_VERSION (no drift)' {
        $v = (Get-DevDepVersions).Pester
        $script:Ci | Should -Match ([regex]::Escape("PESTER_VERSION: `"$v`""))
    }
    It 'pins PSScriptAnalyzer to the CI PSSA_VERSION (no drift)' {
        $v = (Get-DevDepVersions).PSScriptAnalyzer
        $script:Ci | Should -Match ([regex]::Escape("PSSA_VERSION: `"$v`""))
    }
}

Describe 'coverage gate is baseline-driven (B5)' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $RepoRoot 'tests/CoverageGate.ps1')
        $script:Ci = Get-Content (Join-Path $RepoRoot '.github/workflows/ci.yml') -Raw
        $script:Baseline = Read-CoverageBaseline (Get-Content (Join-Path $RepoRoot 'tests/coverage-baseline.json') -Raw)
    }
    It 'ships a parseable, checked-in baseline (coverage bar + test-case floor)' {
        $script:Baseline.MinTotalTests | Should -BeGreaterThan 0
        $script:Baseline.CoveragePercentTarget | Should -BeGreaterThan 0
    }
    It 'CI reads the baseline through the pure gate (not hand-edited literals)' {
        $script:Ci | Should -Match 'Read-CoverageBaseline'
        $script:Ci | Should -Match 'Get-CoverageGateResult'
        # The old magic-number floors must not creep back in.
        $script:Ci | Should -Not -Match '\$minTotal\s*='
        $script:Ci | Should -Not -Match '\$minFiles\s*='
    }
    It 'CI auto-derives the test-file count from the glob (not a stored number)' {
        $script:Ci | Should -Match 'ExpectedFileCount'
        $script:Ci | Should -Match '-Recurse -File -Filter \*\.Tests\.ps1'
    }
}
