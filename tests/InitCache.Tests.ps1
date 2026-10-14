# ============================================================================
#  tests/InitCache.Tests.ps1  -  Get-InitCache's write contract (#287).
#
#  Get-InitCache (core/10-tools.ps1) publishes each tool's init script to a cache
#  file that EVERY shell start reads and, when stale, rewrites. Two shells starting
#  together — the psmux __warm__ pool filling plus the session's first pane — both
#  regenerate the same file, and the loser's Set-Content sharing violation was
#  NON-terminating: it printed at the prompt and the function still returned a path
#  to a file this process never wrote. These tests lift the function out of the
#  fragment (which can't be dot-sourced whole — it runs tool inits at load) and pin
#  the contract: a contended write is silent, never serves a partial file, and a
#  cache-name-only key (-Tool) honours the real binary's mtime.
# ============================================================================

Describe 'Get-InitCache (lifted from core/10-tools.ps1)' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $RepoRoot 'powershell/core/10-tools.ps1'), [ref]$null, [ref]$null)
        $defs = @($ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            ($args[0].Name -replace '^global:', '') -eq 'Get-InitCache'
        }, $true))
        if ($defs.Count -ne 1) { throw "expected exactly one Get-InitCache definition, found $($defs.Count)" }
        # Strip `global:` so the function lands in this suite's scope, not the Pester process.
        . ([scriptblock]::Create(($defs[0].Extent.Text -replace '^function global:', 'function ')))

        # Hermetic stand-ins for the ambient helpers (plain functions, as Maint.Tests does).
        # NOT 05-lib.ps1: its real Test-InMux reads PSMUX_SESSION, so running the suite from
        # a psmux pane would silently take the fast path and test nothing.
        function Test-InMux { $false }
        function Get-DotStringSha256 {
            param([string]$Text)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
            finally { $sha.Dispose() }
        }
        # The ONLY name that resolves to a binary is 'mise' (its stand-in path is set per
        # test); every other key — including the cache-name-only 'mise-shims' — has no Source.
        function Get-DotCmdEntry {
            param([string]$Name)
            $src = if ($Name -eq 'mise') { $script:MiseExe } else { $null }
            [pscustomobject]@{ Found = [bool]$src; Source = $src }
        }
        function Get-Marker { param([scriptblock]$Gen) "# initcache-hash: $(Get-DotStringSha256 $Gen.ToString())" }
        function Get-TempFiles { @(Get-ChildItem -LiteralPath $global:DotfilesInitCacheDir -Filter '*.tmp' -ErrorAction Ignore) }

        $script:SavedDir = $global:DotfilesInitCacheDir
    }
    AfterAll {
        $global:DotfilesInitCacheDir = $script:SavedDir
    }
    BeforeEach {
        $global:DotfilesInitCacheDir = Join-Path $TestDrive "ic-$([guid]::NewGuid().ToString('N'))"
        $script:MiseExe = $null
        $script:Calls   = 0
    }

    Describe 'Get-InitCache: atomic publish (#287)' {
        It 'writes the marker + generator output and returns the path, leaving no temp file' {
            $gen = { 'Write-Output "hi"' }
            $cf = Get-InitCache -Name demo -Generate $gen
            $cf | Should -Be (Join-Path $global:DotfilesInitCacheDir 'demo.ps1')
            $lines = @(Get-Content -LiteralPath $cf)
            $lines[0] | Should -Be (Get-Marker $gen)
            $lines[1] | Should -Be 'Write-Output "hi"'
            Get-TempFiles | Should -HaveCount 0
        }

        It 'a target another writer holds open (<Label>) is skipped silently: null, no error record, no temp, no leaked handle' -Skip:(-not $IsWindows) -ForEach @(
            @{ Label = 'exclusive';    Share = [System.IO.FileShare]::None }
            # What a concurrent Set-Content holds once its own open has hit an IOException and
            # it retried write-only (PowerShell/PowerShell#27947, #24774). Against the old
            # bare Set-Content here this shape produced a NON-terminating
            # GetContentWriterArgumentError that the catch never saw, returned the path
            # anyway, and leaked a write-only stream that kept the file locked for the next
            # shell — the "being used by another process" the issue reports.
            @{ Label = 'write-shared'; Share = [System.IO.FileShare]::Write }
        ) {
            # Pester runs tests under $ErrorActionPreference = Stop, which would turn the very
            # non-terminating error this guards against into a caught one. Model the real
            # shell: the profile loads under the default, Continue.
            $ErrorActionPreference = 'Continue'
            New-Item -ItemType Directory -Force -Path $global:DotfilesInitCacheDir | Out-Null
            $target = Join-Path $global:DotfilesInitCacheDir 'mise-shims.ps1'
            $h = [System.IO.File]::Open($target, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, $Share)
            try   { $res = @(Get-InitCache -Name mise-shims -Generate { 'from-me' } 2>&1) }
            finally { $h.Dispose() }
            @($res | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            @($res | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and $null -ne $_ }) | Should -HaveCount 0
            Get-TempFiles | Should -HaveCount 0
            # The holder is gone, so nothing of OURS may still have the file open: an
            # exclusive open must succeed. (The old code leaked a stream here.)
            $probe = [System.IO.File]::Open($target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $probe.Dispose()
        }

        It 'a complete target a sibling is still reading is served as-is when it carries our marker' -Skip:(-not $IsWindows) {
            # Pester runs tests under $ErrorActionPreference = Stop, which would turn the very
            # non-terminating error this guards against into a caught one. Model the real
            # shell: the profile loads under the default, Continue.
            $ErrorActionPreference = 'Continue'
            # A sibling mid dot-source holds the file open for READ (no FILE_SHARE_DELETE), so
            # the rename over it fails. Renames are atomic, so what is there is complete; it
            # matches our recipe, so it is returned untouched instead of re-spawning the tool.
            $gen = { 'from-sibling' }
            New-Item -ItemType Directory -Force -Path $global:DotfilesInitCacheDir | Out-Null
            $target = Join-Path $global:DotfilesInitCacheDir 'mise-shims.ps1'
            [System.IO.File]::WriteAllText($target, (Get-Marker $gen) + "`nfrom-sibling`n", [System.Text.UTF8Encoding]::new($false))
            $before = [System.IO.File]::ReadAllBytes($target)
            $h = [System.IO.File]::Open($target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try   { $res = @(Get-InitCache -Name mise-shims -Generate $gen 2>&1) }
            finally { $h.Dispose() }
            @($res | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            @($res | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -Be @($target)
            [System.IO.File]::ReadAllBytes($target) | Should -Be $before
            Get-TempFiles | Should -HaveCount 0
        }
    }

    Describe 'Get-InitCache: -Tool gives a cache-name-only key a real freshness check' {
        BeforeEach {
            # A stand-in binary older than the cache, and a cache carrying the recipe's marker:
            # a full hit for anyone who checks both keys.
            $script:MiseExe = Join-Path $TestDrive "mise-$([guid]::NewGuid().ToString('N')).exe"
            Set-Content -LiteralPath $script:MiseExe -Value 'stub'
            (Get-Item -LiteralPath $script:MiseExe).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(-1)
            $script:Gen = { $script:Calls++; 'regen' }
            New-Item -ItemType Directory -Force -Path $global:DotfilesInitCacheDir | Out-Null
            $script:Target = Join-Path $global:DotfilesInitCacheDir 'mise-shims.ps1'
            [System.IO.File]::WriteAllText($script:Target, (Get-Marker $script:Gen) + "`nseed`n", [System.Text.UTF8Encoding]::new($false))
        }

        It 'with -Tool mise, an up-to-date mise-shims cache is NOT regenerated' {
            $cf = Get-InitCache -Name mise-shims -Tool mise -Generate $script:Gen
            $cf | Should -Be $script:Target
            $script:Calls | Should -Be 0
            @(Get-Content -LiteralPath $script:Target)[1] | Should -Be 'seed'
        }

        It 'without -Tool the key has no binary to check and regenerates (default unchanged)' {
            $cf = Get-InitCache -Name mise-shims -Generate $script:Gen
            $cf | Should -Be $script:Target
            $script:Calls | Should -Be 1
            @(Get-Content -LiteralPath $script:Target)[1] | Should -Be 'regen'
        }
    }
}
