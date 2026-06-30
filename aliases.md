# Windows PowerShell Aliases Cheat Sheet

PowerShell functions and `Set-Alias` declarations for common interactive tasks,
sourced from the profile modules. Many tool-backed functions are guarded by
`Test-Cmd` — missing tools fall back gracefully. This covers the most-used
interactive shortcuts; not all profile functions are listed here.

## File Listing (`00-aliases.ps1` — eza / lsd / Get-ChildItem fallback)

> **Note:** Equivalents shown are the `eza` variants. When `eza` is absent, `lsd`
> is used (with different flags); when neither is installed, only `ll` and `la`
> fall back to `Get-ChildItem`.

| Function | Equivalent |
|----------|------------|
| `ls` | `eza --icons --group-directories-first` |
| `l` | `eza --icons --group-directories-first -1` |
| `ll` | `eza --icons --group-directories-first -lh --git` |
| `la` | `eza --icons --group-directories-first -lha --git` |
| `lt` | `eza --tree --level=2` |
| `llt` | `eza --tree --level=3 -lh` |

## File Viewer (bat / Get-Content fallback)

| Function | Equivalent |
|----------|------------|
| `cat` | `bat --paging=never` |
| `catp` | `bat` (paged) |

## Modern CLI Tools

| Function | Equivalent | Requires |
|----------|-----------|----------|
| `grep` | `rg --smart-case` | ripgrep |
| `http` | `xh` | xh |
| `https` | `xh --https` | xh |
| `gmd` | `glow [--pager]` | glow |
| `dns` | `doggo` | doggo |
| `du` | `dust` | dust |
| `pss` | `procs` | procs |
| `watch` | `viddy` | viddy |
| `hex` | `hexyl` | hexyl |
| `loc` | `tokei` | tokei |

## Git Functions (OMZ-compatible)

| Function | Equivalent |
|----------|------------|
| `g` | `git` |
| `gs` | `git status -sb` |
| `gst` | `git status` |
| `gss` | `git status --short` |
| `gsb` | `git status --short --branch` |
| `ga` | `git add` |
| `gaa` | `git add --all` |
| `gc` | `git commit --verbose` |
| `gcm` | `git commit -m` |
| `gco` | `git checkout` |
| `gd` | `git diff` |
| `gl` | `git pull` |
| `glog` | `git log --oneline --decorate --graph` |
| `gp` | `git push` |
| `lg` | `lazygit` |

## Navigation

| Function | Equivalent |
|----------|------------|
| `..` | `Set-Location ..` |
| `...` | `Set-Location ..\..` |
| `....` | `Set-Location ..\..\..` |
| `~` | `Set-Location $HOME` |
| `mkcd <path>` | Create directory and cd into it |
| `dotfiles` | `Set-Location $DOTFILES` |

## Utilities (`20-functions.ps1`)

| Function | Purpose |
|----------|----------|
| `which <cmd>` | Resolve command path |
| `reload` | Reload the PowerShell profile |
| `myip` | External IP address |
| `myip-full` | Full IP info |
| `localips` | All local IP addresses |
| `pbcopy` / `pbpaste` | Clipboard (Mac-style parity) |
| `serve [port]` | Start a local HTTP server |
| `sha256 / sha1 / md5 <file>` | File hash |
| `mkbak <file>` | Timestamped backup |
| `extract <archive>` | Extract any archive format |
| `compress <target>` | Compress to archive |
| `cheat <topic>` | Fetch from cht.sh |
| `fif <pattern>` | Find in files (rg + fzf) |
| `fbr` | Fuzzy git branch checkout |
| `gaf / grf / grsf` | Fuzzy git add / restore / restore --staged |

## Package Management (`30-windows.ps1`)

### Scoop

| Function | Equivalent |
|----------|------------|
| `sci` | `scoop install` |
| `scu` | `scoop update *` |
| `scs` | `scoop search` |
| `scl` | `scoop list` |
| `sccl` | `scoop cleanup * ; scoop cache rm *` |

### Winget

| Function | Equivalent |
|----------|------------|
| `wgi <id>` | `winget install --id <id> -e` |
| `wgu` | `winget upgrade --all --include-unknown` |
| `wgs` | `winget search` |

### Updates

| Function | Purpose |
|----------|----------|
| `up` | Apply all updates (scoop + winget) |
| `update-host` | Apply all updates (wrapper for `up`) |
| `update-check` | Check for available updates without applying |

## WSL Bridge (`31-wsl-bridge.ps1`)

| Function | Purpose |
|----------|----------|
| `kali` | Open Kali WSL shell |
| `wsls` | List WSL distros |
| `wslip` | WSL distro IP address |
| `cdwsl [distro]` | Open WSL distro at current Windows directory (translated to WSL path; falls back to distro default) |
| `wslhome` | Open WSL distro at its home directory (`~`) |
| `hostip` | Windows host IP (as seen from WSL) |
| `wsl-restart` | Restart the WSL subsystem |

## System (`30-windows.ps1`)

| Function | Purpose |
|----------|----------|
| `admin` | Relaunch current shell as Administrator |
| `path` | Print PATH entries one per line |
| `open` | Open file / dir in Explorer (alias: `explorer-here`) |
| `setenv <k> <v>` | Set a persistent user environment variable |
| `getenv <k>` | Read a user environment variable |
| `modules-localize` | Move PowerShell modules off OneDrive |

## psmux (`32-psmux.ps1`)

| Function | Purpose |
|----------|----------|
| `mux` | Attach to or create a psmux session |

## 1Password (`40-op.ps1`)

| Function | Purpose |
|----------|----------|
| `opsecret <ref>` | Read a secret by 1Password reference |
| `openv <item>` | Load item fields as environment variables |
| `optoken <item>` | Get a TOTP token |
| `opssh <key>` | Add an SSH key from 1Password |

## Fuzzy Pickers — Television (`25-television.ps1`)

| Function | Purpose |
|----------|----------|
| `tvim` | Fuzzy-pick a file and open in nvim |
| `ttext` | Fuzzy text search across files |
| `tcd` | Fuzzy cd |
| `trepo` | Fuzzy jump to a git repo |
| `tbranch` | Fuzzy git branch switcher |
| `tenv` | Fuzzy environment variable picker |

## Set-Alias Declarations

| Alias | Points To |
|-------|----------|
| `vim` | `nvim` (if installed) |
| `explorer-here` | `open` |
| `init-cache-clear` | `Clear-InitCache` |
