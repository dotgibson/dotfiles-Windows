# ============================================================================
#  core/55-help.ps1  -  `dothelp`: a scannable, in-shell index of the custom
#  commands this profile adds. The README cheatsheet is great until you're in a
#  shell on a fresh box and can't remember the verb. `dothelp` puts it one word
#  away, grouped by task, with optional filtering:
#
#      dothelp            # the whole grouped index
#      dothelp git        # only rows whose command/description matches "git"
#
#  The catalog (Get-DotfilesHelpData) and everything pure that derives from it —
#  filter tokens, flat picker lines, primary-verb parsing, the "did you mean?"
#  edit-distance matching — now live in the Dotfiles module (B7 stage 2c,
#  powershell/Dotfiles/Help.Helpers.ps1), imported by the profile BEFORE this
#  fragment and unit-tested in tests/Help.Tests.ps1. The interactive `dothelp`
#  verb and the CommandNotFoundAction hook stay here and call them via that
#  module export; add a row to the catalog and it shows up here.
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: dothelp
# requires: Get-DotDidYouMean, Get-DotfilesHelpData, Get-DotHelpFilters, Get-DotHelpFlatLines, Get-DotHelpPrimaryVerb, Write-DotBanner, Write-DotErr, Write-DotHost

function global:dothelp {
    [CmdletBinding()]
    param([string]$Filter, [switch]$Interactive)

    # The catalog + pure helpers come from the Dotfiles module (imported before
    # this fragment). If a degraded load left the module out, there's no catalog to
    # render — warn cleanly instead of throwing 'Get-DotfilesHelpData is not
    # recognized'. (The CommandNotFoundAction hook below already swallows the same
    # case via its own try/catch.)
    if (-not (Get-Command Get-DotfilesHelpData -ErrorAction SilentlyContinue)) {
        Write-Warning 'dothelp: the Dotfiles module is not loaded, so the command catalog is unavailable. Open a new pwsh shell (or check $global:DotfilesLoadErrors) and retry.'
        return
    }

    # Interactive picker: fuzzy-filter every command, and copy the pick to the
    # clipboard so it's ready to paste. Falls back with a hint if fzf is absent.
    if ($Interactive) {
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-DotErr 'interactive dothelp needs fzf' 'scoop install fzf'
            return
        }
        $picked = Get-DotHelpFlatLines |
            fzf --delimiter "`t" --with-nth '1,2' --height '60%' --layout=reverse --border `
                --prompt 'dothelp > ' --preview-window 'hidden'
        if ($picked) {
            $cmd = ($picked -split "`t")[0]
            $verb = Get-DotHelpPrimaryVerb $cmd
            Write-DotHost $cmd -Color Green
            # Best: drop the primary verb on the edit line so it's ready to run or
            # extend (Enter to run) — no paste step. Fall back to the clipboard when
            # PSReadLine isn't loaded (e.g. a non-interactive host).
            $inserted = $false
            if ($verb -and ('Microsoft.PowerShell.PSConsoleReadLine' -as [type])) {
                try {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($verb + ' ')
                    Write-DotHost "  (placed '$verb ' at the prompt — Enter to run)" -Color DarkGray
                    $inserted = $true
                } catch { }
            }
            if (-not $inserted -and (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
                $cmd | Set-Clipboard
                Write-DotHost '  (copied to clipboard)' -Color DarkGray
            }
        }
        return
    }

    $data = Get-DotfilesHelpData
    Write-Host ''
    Write-DotBanner 'dotfiles-Windows' -Subtitle 'custom commands' -Background Blue
    if ($Filter) { Write-DotHost "  (filtered by '$Filter')" -Color DarkGray }
    Write-Host ''

    $shown = 0
    foreach ($group in $data.Keys) {
        $rows = $data[$group]
        if ($Filter) {
            $rows = $rows | Where-Object { $_.Command -match [regex]::Escape($Filter) -or $_.Desc -match [regex]::Escape($Filter) }
        }
        if (-not $rows) { continue }
        Write-DotHost "  $group" -Color Yellow
        $width = ($rows.Command | Measure-Object -Maximum -Property Length).Maximum
        foreach ($r in $rows) {
            $shown++
            Write-DotHost ("    {0,-$width}" -f $r.Command) -Color Green -NoNewline
            Write-DotHost "   $($r.Desc)" -Color Gray
        }
        Write-Host ''
    }
    if ($Filter -and $shown -eq 0) {
        Write-DotHost "  no commands match '$Filter'." -Color DarkYellow
        Write-Host ''
    }
}

# --- CommandNotFoundAction: a gentle "did you mean?" --------------------------
# When you fat-finger one of this profile's verbs, nudge toward the real one and
# point at dothelp — instead of just the bare "not recognized" error. Print-only
# (never substitutes or suppresses the real error) and bulletproof (any failure
# inside is swallowed), so it can't break command resolution. Stays quiet unless
# there's a genuinely close match in the catalog, so random typos don't get noise.
# The ranking helpers (Get-DotDidYouMean / Get-DotHelpFilters) come from the
# Dotfiles module; if it failed to load, the inner call throws and is swallowed,
# so the hook degrades to the host's plain "not recognized" error.
if ($env:FAST_START -ne '1') {
    try {
        $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
            param($CommandName, $eventArgs)
            try {
                if ([string]::IsNullOrWhiteSpace($CommandName)) { return }
                if ($CommandName.Length -lt 2) { return }
                if ($CommandName -match '[\\/:.]') { return }   # skip paths / file-ish names
                # Critical: Get-Command/Test-Cmd probes (used pervasively across the
                # profile) raise THIS SAME event for every missing tool. Such probes
                # run from inside a script/function, so their call stack has a frame
                # with a ScriptName; a command typed at the prompt does not. Only react
                # to the prompt case — otherwise every tool probe spews suggestions.
                if (@(Get-PSCallStack | Select-Object -Skip 1 | Where-Object { $_.ScriptName }).Count -gt 0) { return }
                $suggest = Get-DotDidYouMean -Name $CommandName -Candidates (Get-DotHelpFilters)
                if ($suggest) {
                    Write-DotHost ("  did you mean: {0}?   (run 'dothelp' for the full index)" -f ($suggest -join ', ')) -Color DarkYellow
                }
            } catch { }
        }
    } catch { }
}
