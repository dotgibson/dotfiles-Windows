# ============================================================================
#  core/55-help.ps1  -  `dothelp`: a scannable, in-shell index of the custom
#  commands this profile adds. The README cheatsheet is great until you're in a
#  shell on a fresh box and can't remember the verb. `dothelp` puts it one word
#  away, grouped by task, with optional filtering:
#
#      dothelp            # the whole grouped index
#      dothelp git        # only rows whose command/description matches "git"
#
#  The catalog lives in Get-DotfilesHelpData (pure data) so it's unit-tested and
#  trivial to extend — add a row there and it shows up here.
# ============================================================================

function global:Get-DotfilesHelpData {
    # Ordered groups -> rows of @{ Command; Desc }. Curated to mirror the README
    # cheatsheet; keep new user-facing verbs listed here so they stay discoverable.
    [System.Collections.Specialized.OrderedDictionary]$g = [ordered]@{}
    $g['Listing & files'] = @(
        @{ Command = 'll / la / lt'; Desc = 'eza listings (long / all+hidden / tree)' }
        @{ Command = 'cat / catp';   Desc = 'bat (no-pager / paged)' }
        @{ Command = 'du / hex / loc'; Desc = 'dust disk-usage / hexyl / tokei LOC' }
        @{ Command = 'extract / compress'; Desc = 'archive in/out (ouch, with fallbacks)' }
        @{ Command = 'mkbak <f>';    Desc = 'timestamped backup copy of a file' }
    )
    $g['Navigation'] = @(
        @{ Command = 'z <dir>';      Desc = 'zoxide jump (cd is rebound to z)' }
        @{ Command = '.. / ... / ~'; Desc = 'up one/two dirs / home' }
        @{ Command = 'mkcd <dir>';   Desc = 'make a directory and cd into it' }
        @{ Command = 'dotfiles';     Desc = 'cd to the dotfiles repo' }
    )
    $g['Git'] = @(
        @{ Command = 'g / gs / gl';  Desc = 'git / status -sb / pretty log' }
        @{ Command = 'ga / gaa / gc / gcm'; Desc = 'add / add --all / commit / commit -m' }
        @{ Command = 'gco / gd / gp / gpl'; Desc = 'checkout / diff / push / pull' }
        @{ Command = 'lg';           Desc = 'lazygit' }
        @{ Command = 'fbr';          Desc = 'fuzzy git-branch checkout' }
    )
    $g['Find / fuzzy'] = @(
        @{ Command = 'Ctrl+t / Ctrl+r'; Desc = 'fzf file picker / history search' }
        @{ Command = 'fif <term>';   Desc = 'find-in-files, open the hit in nvim' }
        @{ Command = 'tvim / ttext'; Desc = 'television: pick file / search contents' }
        @{ Command = 'tcd / trepo / tbranch'; Desc = 'television: dir / repo / branch' }
    )
    $g['Network / HTTP'] = @(
        @{ Command = 'http / https'; Desc = 'xh (Rust HTTPie)' }
        @{ Command = 'dns <name>';   Desc = 'doggo (modern dig)' }
        @{ Command = 'myip / localips'; Desc = 'public IP / local interface IPs' }
        @{ Command = 'serve [port]'; Desc = 'HTTP server in CWD, prints LAN URL' }
    )
    $g['Updates & maintenance'] = @(
        @{ Command = 'up [-y] / up -n'; Desc = 'apply scoop + winget updates (-n/-Preview: list only)' }
        @{ Command = 'update-check'; Desc = 'force the "updates available" check now' }
        @{ Command = 'maint-install [HH:MM]'; Desc = 'register the daily maint task' }
        @{ Command = 'maint-run / maint-log / maint-status'; Desc = 'run / tail / next-run' }
        @{ Command = 'shell-bench / prof-trace'; Desc = 'measure cold-start / trace load' }
        @{ Command = 'dotfiles-doctor [-Fix]'; Desc = 'health-check this setup (and auto-remediate)' }
    )
    $g['Packages'] = @(
        @{ Command = 'scs / sci / scl / scu'; Desc = 'scoop search / install / list / update' }
        @{ Command = 'wgs / wgi / wgu'; Desc = 'winget search / install / upgrade-all' }
    )
    $g['Secrets & transfer'] = @(
        @{ Command = 'opsecret / optoken'; Desc = '1Password: read secret / copy TOTP' }
        @{ Command = 'openv / opssh'; Desc = '1Password: run with .env.op / list SSH keys' }
        @{ Command = 'age-enc / age-dec'; Desc = 'age file encrypt / decrypt' }
        @{ Command = 'send / recv';  Desc = 'croc peer-to-peer file transfer' }
    )
    $g['WSL bridge'] = @(
        @{ Command = 'kali / debian'; Desc = 'jump into a WSL distro' }
        @{ Command = 'cdwsl [distro]'; Desc = 'enter WSL at the current directory' }
        @{ Command = 'wsls / hostip'; Desc = 'distro status / host LAN IP' }
    )
    $g['psmux (multiplexer)'] = @(
        @{ Command = 'mux [session]'; Desc = 'attach-or-create a psmux session' }
        @{ Command = 'psmux-pill-enable / -disable'; Desc = 'operator/VPN status pill' }
    )
    $g['Shell'] = @(
        @{ Command = 'reload';       Desc = 'reload the PowerShell profile' }
        @{ Command = 'which <name>'; Desc = 'resolve a command (source / kind)' }
        @{ Command = 'dothelp [filter]'; Desc = 'this index (-i for an fzf picker)' }
    )
    return $g
}

# --- Get-DotHelpFilters -------------------------------------------------------
# The set of useful `dothelp <filter>` arguments: every group name plus every
# individual command verb (so "ll / la / lt" yields ll, la, lt). Pure, so the
# tab-completer in core/50-completions.ps1 can offer them and it's unit-tested.
function global:Get-DotHelpFilters {
    $data = Get-DotfilesHelpData
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $data.Keys) {
        $out.Add($group)
        foreach ($row in $data[$group]) {
            foreach ($tok in ($row.Command -split '[\s/]+')) {
                # skip placeholders like <dir>, [filter], <name>
                if ($tok -and $tok -notmatch '^[<\[]') { $out.Add($tok) }
            }
        }
    }
    $out | Sort-Object -Unique
}

# --- Get-DotHelpFlatLines -----------------------------------------------------
# One tab-delimited "command<TAB>description<TAB>group" line per entry, for the
# interactive (fzf) picker. Pure, so it's unit-tested.
function global:Get-DotHelpFlatLines {
    $data = Get-DotfilesHelpData
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $data.Keys) {
        foreach ($row in $data[$group]) {
            $out.Add(("{0}`t{1}`t{2}" -f $row.Command, $row.Desc, $group))
        }
    }
    return $out
}

# --- Get-DotHelpPrimaryVerb ---------------------------------------------------
# The first runnable token of a catalog Command cell ("g / gs / gl" -> "g",
# "mkbak <f>" -> "mkbak"), skipping placeholders. Pure, so the interactive picker
# can drop it on the edit line and it's unit-tested.
function global:Get-DotHelpPrimaryVerb {
    [OutputType([string])]
    param([string]$Command)
    if (-not $Command) { return '' }
    foreach ($tok in ($Command -split '[\s/]+')) {
        if ($tok -and $tok -notmatch '^[<\[]') { return $tok }
    }
    return ''
}

# --- "did you mean?" matching (pure) ------------------------------------------
# Get-DotLevenshtein: classic edit distance, used to rank near-misses. Get-DotDid
# YouMean ranks the catalog verbs against a mistyped name (exact-prefix and
# substring beat edit distance) and returns the best few. Both pure, unit-tested;
# the CommandNotFoundAction hook below wires them to the shell.
function global:Get-DotLevenshtein {
    [OutputType([int])]
    param([string]$A, [string]$B)
    $a = "$A"; $b = "$B"
    if ($a -eq $b) { return 0 }
    if (-not $a) { return $b.Length }
    if (-not $b) { return $a.Length }
    $prev = 0..$b.Length
    for ($i = 1; $i -le $a.Length; $i++) {
        $cur = @($i) + (1..$b.Length | ForEach-Object { 0 })
        for ($j = 1; $j -le $b.Length; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $cur[$j] = [Math]::Min([Math]::Min($cur[$j - 1] + 1, $prev[$j] + 1), $prev[$j - 1] + $cost)
        }
        $prev = $cur
    }
    return $prev[$b.Length]
}

function global:Get-DotDidYouMean {
    [OutputType([string[]])]
    param([string]$Name, [string[]]$Candidates, [int]$Max = 3)
    if ([string]::IsNullOrWhiteSpace($Name) -or -not $Candidates) { return @() }
    $n = $Name.ToLowerInvariant()
    # Only word-like verbs of length >= 2 make good suggestions: drop one-char
    # aliases (z/g/l), flags (-n), and symbol verbs (~, .., Ctrl+t) that would
    # otherwise "match" as substrings of a long typo and add noise.
    $usable = $Candidates | Where-Object { $_ -match '^[A-Za-z][A-Za-z0-9_-]{1,}$' }
    $scored = foreach ($c in ($usable | Sort-Object -Unique)) {
        if (-not $c) { continue }
        $cl = $c.ToLowerInvariant()
        if ($cl -eq $n) { continue }
        $score = $null
        if ($cl.StartsWith($n) -or $n.StartsWith($cl)) { $score = 0 }
        # substring only counts when the candidate is long enough to be meaningful
        elseif (($cl.Length -ge 4 -and $n.Contains($cl)) -or ($n.Length -ge 4 -and $cl.Contains($n))) { $score = 1 }
        else {
            $d = Get-DotLevenshtein $n $cl
            # only suggest genuinely close names (scaled to the shorter length)
            if ($d -le [Math]::Max(1, [Math]::Min(2, [int]($n.Length / 3)))) { $score = 2 + $d }
        }
        if ($null -ne $score) { [pscustomobject]@{ Name = $c; Score = $score } }
    }
    @($scored | Sort-Object Score, Name | Select-Object -First $Max -ExpandProperty Name)
}

function global:dothelp {
    [CmdletBinding()]
    param([string]$Filter, [switch]$Interactive)

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
if ($env:FAST_START -ne '1') {
    try {
        $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
            param($CommandName, $eventArgs)
            try {
                if ([string]::IsNullOrWhiteSpace($CommandName)) { return }
                if ($CommandName.Length -lt 2) { return }
                if ($CommandName -match '[\\/:.]') { return }   # skip paths / file-ish names
                $suggest = Get-DotDidYouMean -Name $CommandName -Candidates (Get-DotHelpFilters)
                if ($suggest) {
                    Write-DotHost ("  did you mean: {0}?   (run 'dothelp' for the full index)" -f ($suggest -join ', ')) -Color DarkYellow
                }
            } catch { }
        }
    } catch { }
}
