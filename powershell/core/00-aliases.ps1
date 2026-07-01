# ============================================================================
#  core/00-aliases.ps1  -  cross-fleet aliases (parity with your zsh aliases)
# ============================================================================

# --- load contract (checked by tests/LoadContract.Tests.ps1) ------------------
# provides: Test-Cmd, Test-CmdRuns, ls, l, ll, la, lt, llt, cat, catp, grep, http, https, gmd, dns, du, pss, watch, hex, loc, g, gs, gst, gss, gsb, ga, gaa, gc, gcm, gco, gd, gl, glog, gp, lg, .., ..., ...., ~, mkcd, which, reload, dotfiles
# requires: Write-DotHost
# PowerShell has built-in aliases (ls, cat, cp...) that point at cmdlets.
# We remove the ones we want to override, then define functions that shadow
# them with the modern Rust tools. Functions (not Set-Alias) are used where we
# need to pass default flags.

# --- helper: define a function-backed alias only if the tool exists -----------
# MEMOIZED. Get-Command does a PATH scan for an external tool; the fleet checks the
# same handful of tools (rg, fzf, eza, psmux…) from MANY fragments, and psmux alone
# is probed at top level from three os/ files. Caching the first result per name
# collapses those repeated scans to one lookup each — the single biggest cheap win
# on the cold-start/psmux-split path, and it speeds every guard in every fragment
# that calls Test-Cmd (they all share this definition, dot-sourced at profile scope).
# The cache is a session global reset on every `reload` (this fragment re-runs top
# to bottom), so a tool installed mid-session is picked up after `reload`.
$global:DotfilesCmdCache = @{}
function Test-Cmd {
    param([string]$Name)
    $hit = $global:DotfilesCmdCache[$Name]
    # Distinguish a cached $false from a cache MISS: an absent key returns $null,
    # a cached negative returns [bool]$false. Only a real miss re-scans PATH.
    if ($null -ne $hit) { return $hit }
    $found = [bool](Get-Command $Name -ErrorAction SilentlyContinue)
    $global:DotfilesCmdCache[$Name] = $found
    return $found
}

# --- helper: does a command RESOLVE *and* actually launch? ---------------------
# Test-Cmd only proves a NAME resolves (Get-Command). A dead/dangling shim — e.g.
# a leftover Chocolatey shim whose target was removed, or a scoop shim pointing at
# an uninstalled app — still resolves fine, then errors with "Program X failed to
# run" / "cannot find file" the instant you invoke it. Test-CmdRuns probes one step
# further: it actually launches the tool (a cheap version flag) and reports whether
# it started. Exit code is deliberately ignored — some tools return non-zero for an
# unknown flag yet are perfectly runnable; we only care that the process LAUNCHED,
# so the only failure signal is a thrown native-launch error. Used by fif/fbr and
# dotfiles-doctor so a broken shim surfaces as an actionable hint, not a raw error.
function Test-CmdRuns {
    param([string]$Name, [string[]]$ProbeArgs = @('--version'))
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { return $false }
    # Local Continue so a non-zero exit can't throw under pwsh 7.4+'s
    # $PSNativeCommandUseErrorActionPreference — only a real launch failure should.
    $ErrorActionPreference = 'Continue'
    try { & $Name @ProbeArgs *> $null; return $true }
    catch { return $false }
}

# --- ls -> eza (fall back to lsd, then Get-ChildItem) -------------------------
Remove-Item Alias:ls -ErrorAction SilentlyContinue
if (Test-Cmd eza) {
    function ls  { eza --icons --group-directories-first @args }
    function l   { eza --icons --group-directories-first -1 @args }
    function ll  { eza --icons --group-directories-first -lh --git @args }
    function la  { eza --icons --group-directories-first -lha --git @args }
    function lt  { eza --icons --tree --level=2 @args }
    function llt { eza --icons --tree --level=3 -lh @args }
} elseif (Test-Cmd lsd) {
    function ls  { lsd --group-directories-first @args }
    function ll  { lsd -lh --group-directories-first @args }
    function la  { lsd -lha --group-directories-first @args }
    function lt  { lsd --tree --depth 2 @args }
} else {
    function ll  { Get-ChildItem @args | Format-Table -AutoSize }
    function la  { Get-ChildItem -Force @args | Format-Table -AutoSize }
}

# --- cat -> bat ---------------------------------------------------------------
if (Test-Cmd bat) {
    Remove-Item Alias:cat -ErrorAction SilentlyContinue
    function cat { bat --paging=never @args }
    function catp { bat @args }                         # paged view
    $env:BAT_THEME = 'ansi'   # follow the terminal palette (Tokyo Night)
    # NOTE: MANPAGER is intentionally NOT set here — `sh` doesn't exist on the
    # native Windows host. Wire it inside WSL/git-bash contexts instead.
}

# --- find / grep --------------------------------------------------------------
if (Test-Cmd rg) { function grep { rg --smart-case @args } }
# fd is already named `fd` on Windows (no fd-find rename like Debian)

# --- 2026 modern stack additions (all guarded; classics untouched) ------------
# Parity with Core's aliases.zsh. Each is a distinct verb so it never shadows the
# classic tool in scripts.
if (Test-Cmd xh)    { function http  { xh @args }; function https { xh --https @args } }  # Rust HTTPie — poke APIs/web targets
# render markdown; `gmd` avoids shadowing the built-in `md`/mkdir. Only page when a
# pager exists — glow's default pager is `less`, absent on a stock Windows box, which
# otherwise makes `glow --pager` abort with `exec: "less" not found`.
if (Test-Cmd glow)  { function gmd { if ($env:PAGER -or (Test-CmdRuns less)) { glow --pager @args } else { glow @args } } }
if (Test-Cmd doggo) { function dns   { doggo @args } }                                     # modern dig (DNS recon)
# gron / sd are their own commands (no alias — never shadow sed/jq usage in scripts).

# --- 2026 batch 2: system inspection & utilities (all guarded) ----------------
# dust: visual disk-usage tree (du replacement).
if (Test-Cmd dust)  { function du    { dust @args } }

# procs: colorized, searchable process viewer (ps replacement).
# PowerShell's `ps` alias points at Get-Process; we use `pss` (process-search) to
# avoid shadowing it — `pss nvim`, `pss --tree` etc.
if (Test-Cmd procs) { function pss   { procs @args } }

# viddy: modern `watch` — Windows has no native watch. `watch -n 2 'git status'`.
if (Test-Cmd viddy) { function watch { viddy @args } }

# hexyl: colored hex viewer. `hex binary-file`.
if (Test-Cmd hexyl) { function hex   { hexyl @args } }

# tokei: lines-of-code counter by language. `loc` for muscle memory.
if (Test-Cmd tokei) { function loc   { tokei @args } }

# --- git shorthands (parity with Core's zsh/git.zsh) --------------------------
# Names + semantics track Core so muscle memory carries across the fleet: notably
# `gl` PULLS (Core's omz convention) and `glog` is the graph log — the old
# Windows `gl`=log / `gpl`=pull layout was the one place these drifted.
function g    { git @args }
function gs   { git status -sb @args }            # Windows-kept extra; identical to gsb
function gst  { git status @args }
function gss  { git status --short @args }
function gsb  { git status --short --branch @args }
function ga   { git add @args }
function gaa  { git add --all @args }
function gc   { git commit --verbose @args }
function gcm  { git commit -m @args }
function gco  { git checkout @args }
function gd   { git diff @args }
function gl   { git pull @args }
function glog { git log --oneline --decorate --graph @args }
function gp   { git push @args }
if (Test-Cmd lazygit) { function lg { lazygit @args } }

# --- navigation ---------------------------------------------------------------
function ..    { Set-Location .. }
function ...   { Set-Location ..\.. }
function ....  { Set-Location ..\..\.. }
function ~     { Set-Location $HOME }
function mkcd  { param($p) New-Item -ItemType Directory -Force -Path $p | Out-Null; Set-Location $p }

# --- misc quality-of-life -----------------------------------------------------
function which {
    param($n)
    $cmd = Get-Command $n -ErrorAction SilentlyContinue
    if (-not $cmd) { return }
    # External apps/scripts have a .Source path; our own functions/aliases don't,
    # so fall back to the resolved name + kind (zsh `which` resolves those too).
    if ($cmd.Source) { return $cmd.Source }
    switch ($cmd.CommandType) {
        'Alias'    { "$n -> $($cmd.Definition)" }
        'Function' { "$n is a function" }
        default    { "$n ($($cmd.CommandType))" }
    }
}
function reload { . $PROFILE; Write-DotHost 'profile reloaded' -Color Green }
function dotfiles { Set-Location $global:DOTFILES }

# --- Neovim ----------------------------------------------------------------
# Guarded like every other tool wiring above: only claim `vim` if nvim exists,
# so a fresh box (pre-bootstrap) keeps any real vim on PATH.
if (Test-Cmd nvim) { Set-Alias vim nvim }
