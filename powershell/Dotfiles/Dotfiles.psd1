@{
    RootModule        = 'Dotfiles.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '30e4fff9-3034-48d1-a718-851d57c8f80a'
    Author            = 'Gerrrt'
    Description       = 'dotfiles-Windows shared, non-interactive helper surface (pure rendering + logic). Imported by the PowerShell profile; the interactive layer stays global.'
    PowerShellVersion = '7.0'

    # The curated public surface (single source of truth for what the module
    # exposes). Internal-only helpers are simply omitted here as later stages add
    # them, so they stay module-scoped instead of polluting the session.
    FunctionsToExport = @(
        # rendering / colour / glyphs
        'Write-DotHost'
        'Write-DotBanner'
        'Write-DotRule'
        'Write-DotErr'
        'Write-DotOk'
        'Write-DotWarn'
        'Get-DotGlyph'
        'Test-DotColor'
        'Test-DotUnicode'
        'Get-DotConsoleWidth'
        'Format-DotWrap'
        # prompts / input
        'Read-DotConfirm'
        'Get-DotConfirmAnswer'
        'Test-DotGum'
        'Test-DotEmailish'
        # progress
        'Get-DotSpinnerFrame'
        'Invoke-DotSpinner'
        # pure logic / data
        'Test-SensitiveHistoryLine'
        'Get-DotStringSha256'
        'Get-DotToolNudge'
        'Get-DotfilesLinkPlan'
        'ConvertTo-WslPath'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()
}
