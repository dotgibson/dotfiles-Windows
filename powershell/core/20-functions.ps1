# ============================================================================
#  core/20-functions.ps1  -  general helpers (cross-fleet parity)
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: myip, myip-full, localips, extract, compress, mkbak, sha256, sha1, md5, cheat, pbcopy, pbpaste, serve, fif, fbr, tools
# requires: Get-DotServePlan, Test-Cmd, Test-CmdRuns, Write-DotErr, Write-DotHost

# --- public IP / network quicklook (parity with your `myip` aliases) ----------
function myip      { (Invoke-RestMethod -Uri 'https://ipinfo.io/ip').Trim() }
function myip-full { Invoke-RestMethod -Uri 'https://ipinfo.io/json' }
function localips  {
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
        Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize
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
    if     (Test-Cmd glow) { glow --pager $doc }
    elseif (Test-Cmd bat)  { bat --language markdown $doc }
    elseif (Test-Cmd nvim) { nvim $doc }
    else   { Get-Content $doc }
}
