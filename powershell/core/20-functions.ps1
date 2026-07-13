# ============================================================================
#  core/20-functions.ps1  -  general helpers (cross-fleet parity)
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: myip, myip-full, localips, ports, extract, compress, mkbak, cdup, fcd, genpw, please, pullall, sha256, sha1, md5, cheat, pbcopy, pbpaste, serve, fif, fbr, gaf, grf, grsf, tools
# requires: Get-DotServePlan, Read-DotConfirm, Test-Cmd, Test-CmdRuns, Write-DotErr, Write-DotHost, Write-DotWarn

# --- public IP / network quicklook (parity with your `myip` aliases) ----------
function myip      { (Invoke-RestMethod -Uri 'https://ipinfo.io/ip').Trim() }
function myip-full { Invoke-RestMethod -Uri 'https://ipinfo.io/json' }
function localips  {
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
        Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize
}

# --- ports: listening sockets + owning process (parity with Core's `ports`) ----
# Core aliases `ports`→`ss -tulpn`/`netstat -tulpn`; the native equivalent is the
# Get-Net* cmdlets. TCP listeners + all UDP endpoints, resolved to a process name.
function ports {
    $rows = [System.Collections.Generic.List[object]]::new()
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $rows.Add([pscustomobject]@{
                Proto   = 'TCP'
                Local   = "$($_.LocalAddress):$($_.LocalPort)"
                OwnerId = $_.OwningProcess
                Process = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
            })
    }
    Get-NetUDPEndpoint -ErrorAction SilentlyContinue | ForEach-Object {
        $rows.Add([pscustomobject]@{
                Proto   = 'UDP'
                Local   = "$($_.LocalAddress):$($_.LocalPort)"
                OwnerId = $_.OwningProcess
                Process = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
            })
    }
    $rows | Sort-Object Proto, Process | Format-Table -AutoSize
}

# --- extract: one command for any archive -------------------------------------
# Delegates to ouch when available (handles 20+ formats, including .tar.xz,
# .zst, .rar, .lzma). Falls back to the built-in switch for the common cases
# so the function still works on a fresh bootstrap before ouch is installed.
function extract {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { Write-DotErr "no such file: $Path"; return }
    if (Test-Cmd ouch) { ouch d $Path; return }
    # fallback: built-in handlers for the most common formats
    $full = (Resolve-Path $Path).Path
    switch -Regex ($full) {
        '\.zip$'              { Expand-Archive -Path $full -DestinationPath . -Force; break }
        '\.(tar\.gz|tgz)$'   { tar -xzf $full; break }
        '\.(tar\.bz2|tbz)$'  { tar -xjf $full; break }
        '\.tar$'             { tar -xf  $full; break }
        '\.7z$'              { if (Test-Cmd 7z) { 7z x $full } else { Write-DotErr '7z not installed' 'scoop install 7zip' }; break }
        default              { Write-DotErr "don't know how to extract: $full" 'install ouch for broader format support: scoop install ouch' }
    }
}

# --- compress: create an archive from files/dirs ------------------------------
# Requires ouch. Format is inferred from the output extension:
#   compress src/ output.tar.gz
#   compress a.txt b.txt bundle.zip
function compress {
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Targets
    )
    if (-not (Test-Cmd ouch)) { Write-DotErr 'compress needs ouch' 'scoop install ouch'; return }
    if ($Targets.Count -lt 2) { Write-DotErr 'usage: compress <source...> <output-archive>'; return }
    ouch c @Targets
}

# --- mkbak: timestamped backup of a file --------------------------------------
function mkbak {
    param([Parameter(Mandatory)][string]$Path)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item $Path "$Path.$stamp.bak"
    Write-DotHost "-> $Path.$stamp.bak" -Color Green
}

# --- cdup: climb N directories (parity with Core's `cdup`) --------------------
# cdup 3 == cd ..\..\.. ; N defaults to 1 and must be a positive integer (a typo'd
# `cdup x` should say so, not silently no-op).
function cdup {
    param([string]$n = '1')
    if ($n -notmatch '^\d+$' -or [int]$n -lt 1) {
        Write-DotErr "cdup: count must be a positive integer (got '$n')" 'usage: cdup [n]'
        return
    }
    Set-Location (('..' + [IO.Path]::DirectorySeparatorChar) * [int]$n)
}

# --- fcd: fuzzy-cd into any subdirectory (parity with Core's `fcd`) ------------
# fd feeds fzf when present; degrades to Get-ChildItem -Recurse on a bare box.
function fcd {
    if (-not (Test-Cmd fzf)) { Write-DotErr 'fcd needs fzf' 'scoop install fzf'; return }
    $dir = if (Test-Cmd fd) {
        fd --type d --hidden --exclude .git | fzf
    } else {
        Get-ChildItem -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
            Select-Object -ExpandProperty FullName | fzf
    }
    if ($dir) { Set-Location $dir }
}

# --- genpw: random alphanumeric password (parity with Core's `genpw`) ---------
# Default length 16. Uses the cryptographic RNG (stronger than Core's openssl path,
# and always present on .NET) so this is safe for real secrets.
function genpw {
    param([string]$Length = '16')
    if ($Length -notmatch '^\d+$' -or [int]$Length -lt 1) {
        Write-DotErr "genpw: length must be a positive integer (got '$Length')" 'usage: genpw [length]'
        return
    }
    $len = [int]$Length
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
    $bytes = [byte[]]::new($len)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

# --- please: re-run the last command elevated (parity with Core's `please`) ----
# Core runs `sudo !!`; the host analog is an elevated re-run. PREVIEWS + CONFIRMS
# first (this runs your previous line as admin). Prefers native `sudo` (Windows 11)
# for an inline run; otherwise relaunches via UAC in a new elevated window.
function please {
    $last = (Get-History | Select-Object -Last 1).CommandLine
    if ([string]::IsNullOrWhiteSpace($last)) {
        Write-DotErr 'please: no previous command to re-run'
        return
    }
    Write-DotWarn "about to run elevated:  $last"
    if (-not (Read-DotConfirm 'proceed?')) { Write-DotWarn 'please: cancelled'; return }
    if (Test-Cmd sudo) { sudo pwsh -NoLogo -Command $last }
    else { Start-Process pwsh -Verb RunAs -ArgumentList '-NoExit', '-Command', $last }
}

# --- pullall: fast-forward every git repo under a dir, in parallel ------------
# Parity with Core's `pullall`: for each repo it prunes deleted remote branches,
# stashes tracked changes, switches to the auto-detected trunk (origin/HEAD, else
# main/master/trunk), fast-forwards it, then pops the stash back. The parent dir is
# the arg, else $env:PULLALL_DIR, else the CWD; parallelism is $env:PULLALL_JOBS
# (default 10). Uses pwsh 7's ForEach-Object -Parallel; the worker block runs in a
# bare runspace, so it calls only git + built-in cmdlets (no dotfiles helpers).
function pullall {
    param([string]$Dir)
    $parent = if ($Dir) { $Dir } elseif ($env:PULLALL_DIR) { $env:PULLALL_DIR } else { (Get-Location).Path }
    if (-not (Test-Path $parent -PathType Container)) {
        Write-DotErr "pullall: not a directory: $parent" 'pass a dir, or set $env:PULLALL_DIR'
        return
    }
    $jobs = if ($env:PULLALL_JOBS -match '^\d+$' -and [int]$env:PULLALL_JOBS -ge 1) { [int]$env:PULLALL_JOBS } else { 10 }
    $repos = Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName '.git') }
    if (-not $repos) { Write-DotHost "no git repos under $parent" -Color DarkGray; return }
    Write-DotHost "updating $($repos.Count) git repo(s) under $parent ..." -Color Cyan
    $results = $repos | ForEach-Object -ThrottleLimit $jobs -Parallel {
        Push-Location $_.FullName
        try {
            $name = $_.Name
            git fetch --prune *>$null
            $stashed = $false
            git diff-index --quiet HEAD -- *>$null
            if ($LASTEXITCODE -ne 0) { git stash push -m 'pullall' *>$null; if ($LASTEXITCODE -eq 0) { $stashed = $true } }
            $trunk = (git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null) -replace '^origin/', ''
            if (-not $trunk) { foreach ($b in 'main', 'master', 'trunk') { git show-ref -q --verify "refs/heads/$b"; if ($LASTEXITCODE -eq 0) { $trunk = $b; break } } }
            if (-not $trunk) { $trunk = git rev-parse --abbrev-ref HEAD 2>$null }
            git checkout $trunk *>$null
            if ($LASTEXITCODE -ne 0) { if ($stashed) { git stash pop *>$null }; return "FAIL|$name|could not switch to $trunk" }
            git pull --ff-only origin $trunk *>$null
            $pull = $LASTEXITCODE
            if ($stashed) { git stash pop *>$null }
            if ($pull -eq 0) { "OK|$name|updated $trunk" } else { "FAIL|$name|pull failed (network or non-fast-forward)" }
        } finally { Pop-Location }
    }
    $ok = 0; $fail = 0
    foreach ($r in ($results | Sort-Object)) {
        $p = $r -split '\|', 3
        if ($p[0] -eq 'OK') { Write-Host "  [ok]  $($p[1]): $($p[2])" -ForegroundColor Green; $ok++ }
        else { Write-Host "  [x]   $($p[1]): $($p[2])" -ForegroundColor Red; $fail++ }
    }
    Write-DotHost "pullall: $ok updated, $fail failed" -Color Cyan
}

# --- sha helpers --------------------------------------------------------------
function sha256 { param($Path) (Get-FileHash $Path -Algorithm SHA256).Hash.ToLower() }
function sha1   { param($Path) (Get-FileHash $Path -Algorithm SHA1).Hash.ToLower() }
function md5    { param($Path) (Get-FileHash $Path -Algorithm MD5).Hash.ToLower() }

# --- weather / cheatsheet quicklook (cht.sh) ----------------------------------
function cheat  { param($Topic) Invoke-RestMethod "https://cht.sh/$Topic" }

# --- clipboard parity (`pbcopy`/`pbpaste` muscle memory from the Mac) ---------
function pbcopy  { $input | Set-Clipboard }
function pbpaste { Get-Clipboard }

# --- serve: quick HTTP server in the CWD, printing the host LAN URL -----------
# Parity with Core's `serve`. Binds all interfaces on purpose (ad-hoc file
# transfer): the host's LAN IP is what other machines (and, under mirrored
# networking, WSL) use to reach it. That LAN exposure is the point, so it stays
# the default; `serve -Local` binds 127.0.0.1 only when you don't want anyone
# else on the network to reach the CWD (B13).  serve  /  serve 8080  /  serve -Local
function serve {
    param([int]$Port = 8000, [switch]$Local)
    # LAN-IP lookup only matters for the advertised URL on the default path.
    $ip = if ($Local) { $null } else {
        Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.PrefixOrigin -in 'Dhcp','Manual' -and $_.IPAddress -notlike '169.254.*' } |
            Sort-Object SkipAsSource | Select-Object -First 1 -ExpandProperty IPAddress
    }
    $plan = Get-DotServePlan -Port $Port -Local:$Local -LanIp $ip
    Write-DotHost "serving $((Get-Location).Path) on port $Port  (Ctrl-C to stop)" -Color Cyan
    if ($plan.Url) {
        $tag = if ($plan.Scope -eq 'local') { 'local only' } else { 'lan' }
        Write-DotHost "  -> $($plan.Url)   ($tag)" -Color Green
    }
    if (-not ((Test-Cmd python) -or (Test-Cmd python3))) {
        Write-DotErr 'python not found' 'scoop install python'; return
    }
    # finally: print a clean line on Ctrl-C (or normal exit) instead of dumping
    # the user back at a bare prompt with no acknowledgement the server stopped.
    try {
        if (Test-Cmd python) { python -m http.server $Port $plan.BindArgs }
        else { python3 -m http.server $Port $plan.BindArgs }
    } finally {
        Write-DotHost "`nserver stopped." -Color DarkGray
    }
}

# --- fif: find text inside files (rg -> fzf -> open in nvim) -------------------
function fif {
    param([Parameter(Mandatory)][string]$Term)
    if (-not (Test-Cmd rg) -or -not (Test-Cmd fzf)) { Write-DotErr 'fif needs rg + fzf' 'scoop install ripgrep fzf'; return }
    # A tool can RESOLVE on PATH yet fail to launch (a dead Chocolatey/scoop shim
    # shadowing the real binary) — that's the "Program rg.exe failed to run" case.
    # Catch it here with an actionable hint instead of letting the raw Win32 error
    # bubble out of the pipeline.
    foreach ($t in 'rg', 'fzf') {
        if (-not (Test-CmdRuns $t)) {
            Write-DotErr "fif: '$t' is on PATH but won't launch (broken shim?)" 'reset the scoop shim (e.g. scoop reset ripgrep / scoop reset fzf) or remove a stale Chocolatey/duplicate copy shadowing it; run dotfiles-doctor for detail'
            return
        }
    }
    $preview = 'bat --style=numbers --color=always "{}"'  # quotes needed for paths with spaces on Windows
    $file = rg --files-with-matches --no-messages $Term |
        fzf --height 80% --layout=reverse --border --prompt 'Text Match > ' `
            --preview $preview --preview-window 'right:65%:wrap'
    if (-not $file) { return }
    if (Test-Cmd nvim) { nvim $file }
    else { Write-DotErr 'nvim not found to open the match' "the file is: $file" }
}

# --- fbr: fuzzy git branch checkout -------------------------------------------
function fbr {
    if (-not (Test-Cmd fzf)) { Write-DotErr 'fbr needs fzf' 'scoop install fzf'; return }
    # Same dead-shim guard as fif: fzf can resolve yet fail to launch (the
    # "cannot find file at ...\fzf.exe" case when a Chocolatey/duplicate shim
    # shadows the working scoop binary). Fail with a fix hint, not a Win32 error.
    if (-not (Test-CmdRuns fzf)) {
        Write-DotErr "fbr: 'fzf' is on PATH but won't launch (broken shim?)" 'reset the scoop shim (scoop reset fzf) or remove a stale Chocolatey/duplicate fzf shadowing it; run dotfiles-doctor for detail'
        return
    }
    # Clean the branch names in PowerShell BEFORE handing them to fzf, so {} in
    # the preview (run by fzf's shell, not PowerShell) is already a valid ref.
    $branches = git branch --all 2>$null |
        Where-Object { $_ -notmatch 'HEAD' } |
        ForEach-Object { ($_ -replace '^[*+ ]+', '' -replace 'remotes/[^/]+/', '').Trim() } |
        Sort-Object -Unique
    if (-not $branches) { return }
    $branch = $branches | fzf --preview 'git log --oneline --color=always -20 {}'
    if ($branch) { git checkout $branch.Trim() }
}

# --- gaf / grf / grsf: fuzzy git stage / restore / unstage --------------------
# Cross-shell parity (PARITY.md) with Core's zsh git.zsh helpers: multi-select files
# from the relevant set with a diff preview, then act on the picks. TAB toggles in fzf;
# each acts on one path at a time (no xargs/-0 needed — pwsh hands fzf's lines straight
# to git). Same dead-shim guard as fif/fbr.
function gaf {
    # fuzzy `git add` — pick from modified + untracked
    if (-not (Test-Cmd fzf)) { Write-DotErr 'gaf needs fzf' 'scoop install fzf'; return }
    if (-not (Test-CmdRuns fzf)) { Write-DotErr "gaf: 'fzf' is on PATH but won't launch (broken shim?)" 'reset the scoop shim (scoop reset fzf); run dotfiles-doctor for detail'; return }
    $files = git ls-files --modified --others --exclude-standard 2>$null |
        fzf --multi --prompt 'add> ' --preview 'git diff --color=always -- "{}"'
    if ($files) { $files | ForEach-Object { git add -- $_ }; git status --short }
}
function grf {
    # fuzzy `git restore` — discard unstaged changes to picked files
    if (-not (Test-Cmd fzf)) { Write-DotErr 'grf needs fzf' 'scoop install fzf'; return }
    if (-not (Test-CmdRuns fzf)) { Write-DotErr "grf: 'fzf' is on PATH but won't launch (broken shim?)" 'reset the scoop shim (scoop reset fzf); run dotfiles-doctor for detail'; return }
    $files = git diff --name-only 2>$null |
        fzf --multi --prompt 'restore> ' --preview 'git diff --color=always -- "{}"'
    if ($files) { $files | ForEach-Object { git restore -- $_ } }
}
function grsf {
    # fuzzy `git restore --staged` — unstage picked files
    if (-not (Test-Cmd fzf)) { Write-DotErr 'grsf needs fzf' 'scoop install fzf'; return }
    if (-not (Test-CmdRuns fzf)) { Write-DotErr "grsf: 'fzf' is on PATH but won't launch (broken shim?)" 'reset the scoop shim (scoop reset fzf); run dotfiles-doctor for detail'; return }
    $files = git diff --staged --name-only 2>$null |
        fzf --multi --prompt 'unstage> ' --preview 'git diff --staged --color=always -- "{}"'
    if ($files) { $files | ForEach-Object { git restore --staged -- $_ } }
}

# --- tools: open the host tool docs (docs/TOOLS.md) ---------------------------
# The README cheatsheet advertises `tools` ("open the host tool docs"); this is
# its implementation. Renders the vendored docs\TOOLS.md with glow when present
# (same renderer as `gmd`), falling back to bat, then nvim, then a plain dump — so
# it still works on a fresh box before the markdown viewers are installed.
function tools {
    $doc = if ($global:DOTFILES) { Join-Path $global:DOTFILES 'docs\TOOLS.md' } else { $null }
    if (-not $doc -or -not (Test-Path $doc)) {
        Write-DotErr 'tools: docs\TOOLS.md not found' 'check $global:DOTFILES (re-run install.ps1)'
        return
    }
    # Gate each renderer on Test-CmdRuns, not Test-Cmd: a dead/dangling shim
    # (glow/bat/nvim) resolves yet won't launch, so a resolution-only check would
    # pick it and break the fallback chain instead of falling through to the next.
    #
    # glow/bat page through $PAGER (default `less`), which isn't on a stock Windows
    # box — `glow --pager` then aborts with `exec: "less" not found`. Only ask for
    # paging when a pager actually exists; otherwise render inline.
    $canPage = [bool]($env:PAGER -or (Test-CmdRuns less))
    if     (Test-CmdRuns glow) { if ($canPage) { glow --pager $doc } else { glow $doc } }
    elseif (Test-CmdRuns bat)  {
        if ($canPage) { bat --language markdown $doc }
        else          { bat --language markdown --paging=never $doc }
    }
    elseif (Test-CmdRuns nvim) { nvim $doc }
    else   { Get-Content $doc }
}
