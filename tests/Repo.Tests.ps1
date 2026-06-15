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
        ($w | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
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
