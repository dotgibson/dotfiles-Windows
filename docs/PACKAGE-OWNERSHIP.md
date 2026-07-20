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

## A manager listing something is not proof it installed it

The corollary, and the one that took longest to see. **An absent ARP entry is as
informative as a shared one** — it tells you which manager can actually remove a
package, and therefore which manager's claim is real.

Julia is the worked example. Its installer is Inno Setup with
`CreateUninstallRegKey=no`: it writes `uninstall\unins000.exe` and registers
*nothing* in ARP. So the ARP entry that existed on 2026-07-20 was
**Chocolatey's**, describing a directory choco had installed into. winget had
been listing Julia the whole time on the strength of someone else's registration.

Two consequences follow, and both bit:

1. Removing choco's Julia deleted the files, because choco genuinely owned that
   install — winget's listing was never a second copy.
2. Afterwards `winget uninstall` failed with `0x800401f5 Application not found`
   **and could not be fixed by reinstalling**, because a fresh install still
   registers nothing for winget to correlate against.

The record was cleared by supplying the missing registration — a single HKCU key
with `UninstallString` pointing at the real `unins000.exe`, so winget could
correlate, run Julia's own uninstaller, and drop its tracking entry in one
supported operation. The key is not removed by Inno afterwards (it did not create
it), so delete it yourself once winget reports success.

Do **not** edit winget's tracking database to fix this class of problem — it
lives under the App Installer package data:

```text
%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\Microsoft.Winget.Source_8wekyb3d8bbwe\installed.db
```

It is held open by a running service, and corrupting it breaks winget entirely
rather than just the offending row.

Before removing anything, ask which manager can *uninstall* it:

```powershell
# No ARP entry => winget/choco cannot remove it, whatever `list` claims.
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
  Where-Object { $_.DisplayName -match '<name>' -or $_.InstallLocation -match '<name>' } |
  Select-Object DisplayName, InstallLocation, UninstallString
```

## The stale registration that must NOT be cleaned: BullGuard

There is a third registry of installed software besides ARP and winget's tracking
db — **Windows Security Center** — and it holds a ghost this repo deliberately
leaves alone.

`Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct`
reports **BullGuard Antivirus** as `enabled=ON, definitions=OUT-OF-DATE`. It is
entirely fictional: both executables it names are absent, and there is no
service, process, install directory, or ARP entry. BullGuard was discontinued
(folded into Norton) and its uninstaller never called
`WscUnRegisterSecurityProvider`. The leftover key is:

```text
HKLM\SOFTWARE\Microsoft\Security Center\Provider\Av\{0C5A09FB-657F-B94D-DF1B-BB843C6EE0E4}
```

**It cannot be deleted, and that is correct behaviour.** The ACL grants `Delete`
to exactly one identity, `NT SERVICE\wscsvc` — the Security Center service.
SYSTEM gets only `SetValue, CreateSubKey, ReadKey`; Administrators are not in the
ACL at all. Verified on 2026-07-20: `reg delete` fails as Administrator, fails as
`NT AUTHORITY\SYSTEM` (via `gsudo -s`), and restarting `wscsvc` does not purge it.

That protection exists so malware cannot silently deregister your antivirus.
Taking ownership to grant yourself `Delete` defeats it. Do not do that — "it is
only a stale entry" is exactly the reasoning the control is built to resist.

### The real risk, and the cheap mitigation

Nothing is wrong today: Malwarebytes is active with current definitions, and
Defender is correctly passive (`AMRunningMode: Not running`) because a third-party
AV owns protection.

The danger is conditional. Windows decides whether to re-enable Defender based on
whether any *other* product claims to be enabled — and this ghost claims exactly
that. **If Malwarebytes is ever removed or replaced, Defender may not turn itself
back on, leaving no antivirus at all while Security Center believes otherwise.**

So after any antivirus change, check explicitly rather than assuming:

```powershell
Get-MpComputerStatus | Select-Object AMRunningMode, AntivirusEnabled, RealTimeProtectionEnabled
```

If that reports `Not running` and no other AV is installed, re-enable Defender by
hand in Windows Security.

Two legitimate ways it could still disappear, neither worth doing for its own
sake: a Windows in-place upgrade/repair install rebuilds the Security Center
store, and Malwarebytes' own `mb-clean` support tool has historically cleared
stale WSC registrations (vendor tooling, running with the privileges intended for
the job).

A backup of the key is at `~\pkg-backup-2026-07-20\bullguard-av-registration.reg`.

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
