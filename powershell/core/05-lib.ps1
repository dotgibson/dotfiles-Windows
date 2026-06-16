# ============================================================================
#  core/05-lib.ps1  -  pure, side-effect-free helpers shared across the layers.
#
#  Loads right after 00-aliases (so Test-Cmd exists) and before everything that
#  uses these helpers. NOTHING here shells out, registers a hook, or prints on
#  load — which is also what lets the test suite dot-source this one file in
#  isolation and assert on the functions (see tests/Lib.Tests.ps1).
# ============================================================================

# --- Test-SensitiveHistoryLine ------------------------------------------------
# Decide whether a command line is sensitive enough to keep OUT of the saved
# PSReadLine history file (it stays usable in-session; it just isn't persisted).
# The PSReadLine analog of Core's HISTORY_IGNORE.
#
# The earlier inline regex matched bare substrings, so it quietly dropped the
# everyday `pwd` command (and anything containing "pass"/"creds"/...), meaning
# common navigation never made it into history. This version is word-boundaried
# and context-aware: secret-bearing KEYWORDS only as whole words, secret-carrying
# FLAGS only when dash-prefixed, and the 1Password live-read verbs as phrases.
# `pwd`, `compass`, "first pass", etc. are no longer false positives.
function global:Test-SensitiveHistoryLine {
    [OutputType([bool])]
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }

    # 1Password CLI commands that surface live secrets into the terminal.
    if ($Line -match '(?i)\bop\s+(read|item|get|inject|run)\b') { return $true }

    # Secret-bearing keywords. Boundaries are LETTER-only lookarounds, not \b, so
    # digits/underscores/spaces count as separators: this matches GH_TOKEN and
    # OPENAI_API_KEY and "private key", but NOT "compass" or "first pass". Note the
    # deliberate absence of bare `pwd`/`pass` — those are matched as flags below,
    # never as the standalone `pwd` command or the word "pass".
    if ($Line -match '(?i)(?<![a-z])(passwd|password|secret|token|bearer|credentials?|authorization|oauth|jwt|api[\s_-]?key|access[\s_-]?key|secret[\s_-]?key|client[\s_-]?secret|private[\s_-]?key)(?![a-z])') { return $true }

    # Secret-carrying command-line flags: --password / -pwd / --token / -secret …
    # Requires a leading dash so the bare `pwd` command can never match.
    if ($Line -match '(?i)(^|\s)-{1,2}(password|passwd|pwd|pass|token|secret|apikey)\b') { return $true }

    return $false
}

# --- Test-DotEmailish ---------------------------------------------------------
# A deliberately loose "does this look like an email?" check for the install-time
# git-identity prompt — enough to catch a fat-fingered "me@" or a name typed into
# the email field, without pretending to be RFC 5322. Pure, so it's unit-tested.
function global:Test-DotEmailish {
    [OutputType([bool])]
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    return ($Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

# --- Get-DotfilesLinkPlan -----------------------------------------------------
# THE single source of truth for every symlink this repo wires: one ordered list
# that install.ps1 creates, uninstall.ps1 removes, and dotfiles-doctor verifies.
# Before this existed the set was hand-maintained in three places, so adding a
# link meant editing all three or silently drifting (uninstall would orphan it,
# doctor would never check it). Pure: every path is derived from injected roots,
# so it's unit-tested and the consumers can't disagree about what "the links" are.
#
# Uses [IO.Path]::Combine (a pure string join), NOT Join-Path: Join-Path resolves
# the drive PROVIDER and throws DriveNotFoundException for a path on a drive that
# doesn't exist on this host — which is exactly what the tests inject (H:, L:, D:).
#
# ParentMustExist flags a link whose parent we must NOT create on demand: the
# Windows Terminal LocalState dir only exists when WT (Store build) is installed,
# so install.ps1 skips that row rather than materializing an empty tree.
function global:Get-DotfilesLinkPlan {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$HomeDir      = $HOME,
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$Documents    = [Environment]::GetFolderPath('MyDocuments')
    )
    $join = { param($a, $b) [System.IO.Path]::Combine($a, $b) }
    if (-not $Documents)    { $Documents    = & $join $HomeDir 'Documents' }
    if (-not $LocalAppData) { $LocalAppData = & $join $HomeDir 'AppData\Local' }
    $repo = { param($p) & $join $RepoRoot $p }
    $row  = {
        param($Name, $Target, $Link, $ParentMustExist = $false)
        [pscustomobject]@{ Name = $Name; Target = $Target; Link = $Link; ParentMustExist = $ParentMustExist }
    }
    @(
        & $row 'PowerShell profile'        (& $repo 'powershell\profile.ps1')        (& $join $Documents    'PowerShell\Microsoft.PowerShell_profile.ps1')
        & $row 'nvim config'               (& $repo 'nvim')                          (& $join $LocalAppData 'nvim')
        & $row '.gitconfig'                (& $repo 'git\.gitconfig')                (& $join $HomeDir      '.gitconfig')
        & $row '.gitignore_global'         (& $repo 'git\.gitignore_global')         (& $join $HomeDir      '.gitignore_global')
        & $row 'ssh config'                (& $repo 'ssh\config')                    (& $join $HomeDir      '.ssh\config')
        & $row 'psmux.conf'                (& $repo 'psmux\psmux.conf')              (& $join $HomeDir      '.config\psmux\psmux.conf')
        & $row 'psmux.reset.conf'          (& $repo 'psmux\psmux.reset.conf')        (& $join $HomeDir      '.config\psmux\psmux.reset.conf')
        & $row 'psmux scripts'             (& $repo 'psmux\scripts')                 (& $join $HomeDir      '.config\psmux\scripts')
        & $row 'Windows Terminal settings' (& $repo 'windows-terminal\settings.json') (& $join $LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json') $true
    )
}

# --- defensive output: NO_COLOR + non-Unicode terminals -----------------------
# Two universal escape hatches so the colored, glyph-decorated output degrades on
# hosts that can't render it instead of spraying ANSI codes or mojibake:
#   • NO_COLOR (https://no-color.org) — any non-empty value strips colour. We also
#     treat TERM=dumb as no-colour (CI logs, redirected output).
#   • DOTFILES_ASCII=1 — swap the Unicode glyphs (✓ ✗ → •) for ASCII so a legacy
#     codepage console (437/1252) shows readable markers, not boxes.
# Both are PURE given their parameters (defaults read the environment at call
# time), so the decision logic is unit-tested in tests/Lib.Tests.ps1.
function global:Test-DotColor {
    [OutputType([bool])]
    param([string]$NoColor = $env:NO_COLOR, [string]$Term = $env:TERM)
    if (-not [string]::IsNullOrEmpty($NoColor)) { return $false }
    if ($Term -eq 'dumb') { return $false }
    return $true
}

function global:Test-DotUnicode {
    [OutputType([bool])]
    param([string]$Ascii = $env:DOTFILES_ASCII)
    return ($Ascii -ne '1')
}

# Status/decoration glyphs, resolved once here so every renderer agrees and the
# ASCII fallback is in exactly one place.
function global:Get-DotGlyph {
    param(
        [Parameter(Mandatory)][ValidateSet('ok', 'warn', 'fail', 'arrow', 'bullet', 'pkg')][string]$Name,
        [bool]$Unicode = (Test-DotUnicode)
    )
    $uni = @{ ok = '✓'; warn = '!'; fail = '✗'; arrow = '→'; bullet = '•'; pkg = '⇧' }
    $asc = @{ ok = 'OK'; warn = '!'; fail = 'x'; arrow = '->'; bullet = '-'; pkg = '^' }
    if ($Unicode) { $uni[$Name] } else { $asc[$Name] }
}

# Colour-aware Write-Host: honours NO_COLOR by dropping the -ForegroundColor so
# every helper can stay a one-liner instead of branching on colour at each call.
function global:Write-DotHost {
    param(
        [Parameter(Position = 0)][string]$Text = '',
        [string]$Color,
        [switch]$NoNewline
    )
    if ($Color -and (Test-DotColor)) {
        Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewline
    } else {
        Write-Host $Text -NoNewline:$NoNewline
    }
}

# --- Write-DotBanner ----------------------------------------------------------
# The one section header every report uses: an inverse " Title " chip (with an
# optional dimmer subtitle on the same line) when colour is on, degrading to a
# plain "== Title ==" / "== Title :: subtitle ==" under NO_COLOR/TERM=dumb. Pulls
# dotfiles-doctor and dothelp onto a single visual language instead of each
# re-implementing the Test-DotColor branch.
function global:Write-DotBanner {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Subtitle,
        [string]$Background = 'Cyan',
        [string]$Foreground = 'Black',
        [string]$SubtitleColor = 'Cyan'
    )
    if (Test-DotColor) {
        Write-Host " $Text " -ForegroundColor $Foreground -BackgroundColor $Background -NoNewline:([bool]$Subtitle)
        if ($Subtitle) { Write-Host "  $Subtitle" -ForegroundColor $SubtitleColor }
    } elseif ($Subtitle) {
        Write-Host "== $Text :: $Subtitle =="
    } else {
        Write-Host "== $Text =="
    }
}

# --- Write-DotRule ------------------------------------------------------------
# A titled horizontal rule ("-- Summary ─────…"), Unicode by default and ASCII
# under DOTFILES_ASCII, colour-aware via Write-DotHost. One place for the box-rule
# glyph so install/uninstall/maint summaries line up.
function global:Write-DotRule {
    param([string]$Title, [int]$Width = 56, [string]$Color = 'Cyan')
    $ch = if (Test-DotUnicode) { '─' } else { '-' }
    $line = if ($Title) { "-- $Title " + ($ch * $Width) } else { ($ch * $Width) }
    Write-DotHost $line -Color $Color
}

# --- Write-DotErr -------------------------------------------------------------
# One consistent error layout for the interactive helpers: a red "✗ <message>"
# and, when supplied, a dimmed "→ <hint>" telling the user how to fix it (usually
# the exact install command). Replaces the bare, hint-less `Write-Error 'needs x'`
# scattered across the helpers. Glyphs/colour degrade via the helpers above.
# -PassThru returns the composed text (for tests).
function global:Write-DotErr {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Hint,
        [switch]$PassThru
    )
    $x = Get-DotGlyph fail
    $arrow = Get-DotGlyph arrow
    Write-DotHost "  $x " -Color Red -NoNewline
    Write-DotHost $Message -Color Red
    if ($Hint) {
        Write-DotHost "    $arrow " -Color DarkGray -NoNewline
        Write-DotHost $Hint -Color DarkGray
    }
    if ($PassThru) {
        $out = "$x $Message"
        if ($Hint) { $out += "`n$arrow $Hint" }
        return $out
    }
}

# --- Write-DotOk --------------------------------------------------------------
# The success sibling of Write-DotErr/Write-DotWarn: a green "✓ <message>" with an
# optional dimmed "→ <hint>". Replaces the bare `Write-Host '✓ ...' -Foreground
# Green` scattered across the helpers, which ignored NO_COLOR and printed a raw
# glyph under DOTFILES_ASCII. Glyph/colour degrade via the helpers above.
# -PassThru returns the composed text (for tests).
function global:Write-DotOk {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Hint,
        [switch]$PassThru
    )
    $ok = Get-DotGlyph ok
    $arrow = Get-DotGlyph arrow
    Write-DotHost "  $ok " -Color Green -NoNewline
    Write-DotHost $Message -Color Green
    if ($Hint) {
        Write-DotHost "    $arrow " -Color DarkGray -NoNewline
        Write-DotHost $Hint -Color DarkGray
    }
    if ($PassThru) {
        $out = "$ok $Message"
        if ($Hint) { $out += "`n$arrow $Hint" }
        return $out
    }
}

# --- Write-DotWarn ------------------------------------------------------------
# The non-fatal sibling of Write-DotErr: a yellow "! <message>" with an optional
# dimmed "→ <hint>". Used in place of bare Write-Warning at the user-facing entry
# points (install.ps1, the package installer) so warnings share one layout and
# honour NO_COLOR / DOTFILES_ASCII. -PassThru returns the composed text.
function global:Write-DotWarn {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Hint,
        [switch]$PassThru
    )
    $bang = Get-DotGlyph warn
    $arrow = Get-DotGlyph arrow
    Write-DotHost "  $bang " -Color Yellow -NoNewline
    Write-DotHost $Message -Color Yellow
    if ($Hint) {
        Write-DotHost "    $arrow " -Color DarkGray -NoNewline
        Write-DotHost $Hint -Color DarkGray
    }
    if ($PassThru) {
        $out = "$bang $Message"
        if ($Hint) { $out += "`n$arrow $Hint" }
        return $out
    }
}
