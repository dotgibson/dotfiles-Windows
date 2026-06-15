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
