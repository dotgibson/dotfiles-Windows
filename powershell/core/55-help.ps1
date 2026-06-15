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
        @{ Command = 'up [-y]';      Desc = 'apply scoop + winget updates' }
        @{ Command = 'update-check'; Desc = 'force the "updates available" check now' }
        @{ Command = 'maint-install [HH:MM]'; Desc = 'register the daily maint task' }
        @{ Command = 'maint-run / maint-log / maint-status'; Desc = 'run / tail / next-run' }
        @{ Command = 'shell-bench / prof-trace'; Desc = 'measure cold-start / trace load' }
        @{ Command = 'dotfiles-doctor'; Desc = 'health-check this setup' }
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
        @{ Command = 'dothelp [filter]'; Desc = 'this index' }
    )
    return $g
}

function global:dothelp {
    [CmdletBinding()]
    param([string]$Filter)

    $data = Get-DotfilesHelpData
    Write-Host ''
    if (Test-DotColor) {
        Write-Host ' dotfiles-Windows ' -ForegroundColor Black -BackgroundColor Blue -NoNewline
        Write-Host '  custom commands' -ForegroundColor Cyan
    } else {
        Write-Host '== dotfiles-Windows :: custom commands =='
    }
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
