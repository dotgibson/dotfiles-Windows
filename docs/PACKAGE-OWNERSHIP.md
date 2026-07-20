# PACKAGE-OWNERSHIP.md — who owns what, and why

Written 2026-07-20 after retiring Chocolatey from the host. This is the rule
this repo's package layer assumes; `TOOLS.md` covers *which* tools and why,
this covers *which manager installs them*.

## The rule

| Manager     | Owns                                                | Manifest           |
| ----------- | --------------------------------------------------- | ------------------ |
| scoop       | CLI tools, language runtimes, fonts                  | `scoopfile.json`   |
| winget      | GUI apps, system components, shell-integrated things | `winget.json`      |
| chocolatey  | **nothing — retired, do not reintroduce**            | —                  |

Chocolatey was removed because all 40 of its packages duplicated scoop/winget,
its versions lagged (`ripgrep` 14.1.0 vs scoop's 15.2.0), and
`C:\ProgramData\chocolatey\bin` sat early enough on the machine PATH that its
**stale** shims won for `fd`, `julia`, `wget`, `make`, `7z`, and `tree-sitter`.

## Deliberate exceptions to "scoop owns CLI"

Three CLI tools live in winget on purpose. Do not "fix" these:

- **`Git.Git`** — the Program Files install provides Git Bash, Credential
  Manager, and shell integration. Scoop only needs *a* git on PATH.
- **`Microsoft.PowerShell`** — the daily-driver shell; wants the system install.
- **`GNU.Wget2`** — see below.

Python is winget-owned (`C:\Python314`) because the `py` launcher and `uv`
resolve to it. `scoopfile.json` deliberately does **not** declare `python` —
declaring it recreates a duplicate interpreter on every install run.

## `wget` is a shim, not a package

scoop's `wget` manifest downloads from `eternallybored.org`, which resolves to
a sinkhole (`127.250.0.1`) on this host — a DNS-level filter, not a hosts entry.
Rather than bypass it, `wget` is a shim at `~/bin/wget.cmd` forwarding to
winget's `GNU.Wget2`. If you rebuild the host, recreate it:

```bat
@echo off
"%LOCALAPPDATA%\Microsoft\WinGet\Links\wget2.exe" %*
```

## PATH is near its ceiling

Windows truncates the combined machine+user PATH at **2048 characters**. As of
this writing it sits at **1906**. Truncation is silent and looks exactly like a
missing package — entries at the tail simply stop resolving.

Before adding a PATH entry, check the budget:

```powershell
$m = [Environment]::GetEnvironmentVariable('Path','Machine')
$u = [Environment]::GetEnvironmentVariable('Path','User')
"$($m.Length + $u.Length + 1) / 2048"
```

`C:\Program Files\7-Zip` is prepended to the **machine** PATH on purpose: Lua for
Windows ships a 2010-era `7z.exe` at `C:\Program Files (x86)\Lua\5.1`, and since
machine PATH always precedes user PATH, scoop's shim can never win that race.

## Removing a "duplicate" version — read this first

Two registrations with different version strings **do not** imply two installs.
Both of these bit us on 2026-07-20:

- **Julia** — choco reported 1.12.0, winget 1.12.6. One install, two trackers.
  Removing choco's copy deleted the files winget still claimed.
- **7-Zip** — 24.07 and 26.02 both installed to `C:\Program Files\7-Zip`.
  Uninstalling the stale 24.07 registration ran its uninstaller and gutted
  26.02, which kept reporting as installed.

Verify the install directory before removing anything that looks like a stale
version:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
  Where-Object DisplayName -match '<name>' |
  Select-Object DisplayName, DisplayVersion, InstallLocation
```

If two entries share an `InstallLocation`, they are one install. Deregister
rather than uninstall.

## Undeclared on purpose

- `cacert`, `dark`, `innounp`, `mingw` — scoop auto-dependencies, pulled in as
  needed. Declaring them pins transitive deps for no benefit.
- `gzip`, `unzip` — installed only to replace choco shims. `7zip` and `ouch`
  cover archives; not worth manifest space.

## Overlap is intentional

`bottom`/`btop-lhm`/`procs`, `eza`/`lsd`, `delta`/`difftastic`, `fzf`/`television`,
`curl`/`xh` all coexist by design — the rationale for each is in `TOOLS.md`
(e.g. btop-lhm reads hardware sensors; television is deliberately denied Ctrl+R
because atuin owns it). Do not "deduplicate" these without reading that table.

`fastfetch` is declared but referenced nowhere in config — that is correct, it is
a run-by-hand tool.
