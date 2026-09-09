# assets

Media for the project README.

## `demo.gif` — the hero terminal demo

Rendered from [`demo.tape`](demo.tape) with [VHS](https://github.com/charmbracelet/vhs).
Unlike the other nine repos in the fleet, whose tapes dotfiles-core generates from one
shared zsh template, this tape is **hand-authored** — the host layer here is PowerShell and
nothing under `core/` is vendored, so the shared body has nothing to say. It keeps the shared
_shape_ (font, palette, framerate, the three marquee moments, then two of its own) so the
ten heroes read as one family; keep that when editing.

## Filming it

VHS needs a Linux-style pty, so the hero is filmed **from a WSL distro**, with vhs driving the
Windows `pwsh.exe` through interop. The tour itself runs on Windows: the real profile, scoop,
winget, starship and the Nerd Font are the host's.

1. On the WSL side, vhs **v0.10.0** (v0.12.0 exits 0 and writes no file), `ttyd`, `ffmpeg`,
   `gifsicle`, Chromium, and the JetBrainsMono Nerd Font — the same kit that films the Linux
   heroes (dotfiles-core `assets/README.md`, "Filming a sibling hero without its box").
2. A `pwsh` shim first on `$PATH`. vhs runs `pwsh -Login -NoLogo -NoExit -NoProfile -Command …`;
   Windows pwsh accepts all of it. Start it from a Windows directory so interop has a cwd it
   can translate:

   ```sh
   #!/bin/sh
   cd /mnt/c/Users/<you> || exit 1
   exec "/mnt/c/Users/<you>/AppData/Local/Microsoft/WindowsApps/pwsh.exe" "$@"
   ```

3. From the repo root on the WSL side, with the Windows checkout on the branch you want in
   frame (`ll` and `glog -8` film that tree):

   ```sh
   vhs assets/demo.tape
   gifsicle -O3 --lossy=120 --colors 48 assets/demo.gif -o assets/demo.gif
   ```

   That pass is heavier than the `--lossy=80 --colors 64` the Linux heroes get, and it has
   to be: interop hands the tour's output to the pty a few lines at a time, so every scroll
   step is its own full-screen frame where a Linux render gets one jump — the same tour
   comes out of vhs with twice the big frames. 48 colours is still the palette's 20 plus
   antialiasing; the raw ~5 MB lands just under the 2 MiB Core enforces for its own.

The tape sets the profile's knobs before it dot-sources `$PROFILE` — `PSMUX_NO_AUTOLAUNCH`
(or the tour lands in a psmux pane), `DOTFILES_UPDATE_CHECK=0` (no nudge line the tour did
not type), `GIT_PAGER=cat` — and switches PSReadLine predictions off so no ghost text from
past sessions paints under the keystrokes. `scoop update` first, or `up -n` opens with a
stale-bucket warning. Commit the gif **with** any tape change: nothing here dates one against
the other the way Core's audit does for its registered repos, so the pair is on you.
