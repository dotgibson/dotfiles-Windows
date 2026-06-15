# ============================================================================
#  core/20-functions.ps1  -  general helpers (cross-fleet parity)
# ============================================================================

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
    Write-Host "-> $Path.$stamp.bak" -ForegroundColor Green
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
# transfer). The host's LAN IP is what other machines (and, under mirrored
# networking, WSL) use to reach it.  serve  /  serve 8080
function serve {
    param([int]$Port = 8000)
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.PrefixOrigin -in 'Dhcp','Manual' -and $_.IPAddress -notlike '169.254.*' } |
        Sort-Object SkipAsSource | Select-Object -First 1 -ExpandProperty IPAddress)
    Write-Host "serving $((Get-Location).Path) on port $Port  (Ctrl-C to stop)" -ForegroundColor Cyan
    if ($ip) { Write-Host "  -> http://${ip}:$Port/   (lan)" -ForegroundColor Green }
    if (Test-Cmd python) { python -m http.server $Port }
    elseif (Test-Cmd python3) { python3 -m http.server $Port }
    else { Write-DotErr 'python not found' 'scoop install python' }
}

# --- fif: find text inside files (rg -> fzf -> open in nvim) -------------------
function fif {
    param([Parameter(Mandatory)][string]$Term)
    if (-not (Test-Cmd rg) -or -not (Test-Cmd fzf)) { Write-Error 'fif needs rg + fzf'; return }
    $preview = 'bat --style=numbers --color=always "{}"'  # quotes needed for paths with spaces on Windows
    $file = rg --files-with-matches --no-messages $Term |
        fzf --height 80% --layout=reverse --border --prompt 'Text Match > ' `
            --preview $preview --preview-window 'right:65%:wrap'
    if ($file) { nvim $file }
}

# --- fbr: fuzzy git branch checkout -------------------------------------------
function fbr {
    if (-not (Test-Cmd fzf)) { Write-Error 'fbr needs fzf'; return }
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
