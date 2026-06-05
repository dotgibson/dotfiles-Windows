# ============================================================================
#  core/00-aliases.ps1  -  cross-fleet aliases (parity with your zsh aliases)
# ============================================================================
# PowerShell has built-in aliases (ls, cat, cp...) that point at cmdlets.
# We remove the ones we want to override, then define functions that shadow
# them with the modern Rust tools. Functions (not Set-Alias) are used where we
# need to pass default flags.

# --- helper: define a function-backed alias only if the tool exists -----------
function Test-Cmd { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

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
    $env:BAT_THEME = 'ansi'                             # follow the terminal palette (Tokyo Night)
}

# --- find / grep --------------------------------------------------------------
if (Test-Cmd rg) { function grep { rg --smart-case @args } }
# fd is already named `fd` on Windows (no fd-find rename like Debian)

# --- 2026 modern stack additions (all guarded; classics untouched) ------------
# Parity with Core's aliases.zsh. Each is a distinct verb so it never shadows the
# classic tool in scripts.
if (Test-Cmd xh)    { function http { xh @args }; function https { xh --https @args } }  # Rust HTTPie — poke APIs/web targets
if (Test-Cmd glow)  { function md   { glow --pager @args } }                             # render markdown (engagement notes/READMEs)
if (Test-Cmd doggo) { function dns  { doggo @args } }                                    # modern dig (DNS recon)
# gron / sd are their own commands (no alias — never shadow sed/jq usage in scripts).

# --- git shorthands (parity with the fleet) -----------------------------------
function g    { git @args }
function gs   { git status -sb @args }
function ga   { git add @args }
function gaa  { git add --all @args }
function gc   { git commit @args }
function gcm  { git commit -m @args }
function gco  { git checkout @args }
function gd   { git diff @args }
function gl   { git log --oneline --graph --decorate -20 @args }
function gp   { git push @args }
function gpl  { git pull @args }
if (Test-Cmd lazygit) { function lg { lazygit @args } }

# --- navigation ---------------------------------------------------------------
function ..    { Set-Location .. }
function ...   { Set-Location ..\.. }
function ....  { Set-Location ..\..\.. }
function ~     { Set-Location $HOME }
function mkcd  { param($p) New-Item -ItemType Directory -Force -Path $p | Out-Null; Set-Location $p }

# --- misc quality-of-life -----------------------------------------------------
function which { param($n) (Get-Command $n -ErrorAction SilentlyContinue).Source }
function reload { . $PROFILE; Write-Host 'profile reloaded' -ForegroundColor Green }
function dotfiles { Set-Location $global:DOTFILES }
