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
        [Parameter(Mandatory)][ValidateSet('ok', 'warn', 'fail', 'arrow', 'bullet')][string]$Name,
        [bool]$Unicode = (Test-DotUnicode)
    )
    $uni = @{ ok = '✓'; warn = '!'; fail = '✗'; arrow = '→'; bullet = '•' }
    $asc = @{ ok = 'OK'; warn = '!'; fail = 'x'; arrow = '->'; bullet = '-' }
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
