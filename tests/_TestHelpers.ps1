# ============================================================================
#  tests/_TestHelpers.ps1  -  shared fixtures for the Pester suites (B14).
#
#  NOT a *.Tests.ps1 file, so Pester never discovers it as a suite and the CI
#  test-file-count gate (issue #29) doesn't count it. Dot-source it from a
#  suite's BeforeAll — functions defined here then resolve in that suite's
#  nested BeforeAll/It blocks, the same way the dot-sourced install/uninstall
#  helpers already do.
# ============================================================================

# New-DotTestTempDir — a fresh, unique scratch directory created on disk.
# Hoisted from the identical `Join-Path GetTempPath (prefix + guid)` +
# `New-Item -ItemType Directory` boilerplate that Install/Integration/Uninstall/
# Completions each repeated. Returns the directory path; callers create any
# sub-tree they need under it and remove it in their own AfterAll.
function New-DotTestTempDir {
    [OutputType([string])]
    param([string]$Prefix = 'dottest')
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("$Prefix-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dir
}
