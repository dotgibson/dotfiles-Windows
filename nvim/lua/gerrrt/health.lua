-- nvim/lua/gerrrt/health.lua
-- ─────────────────────────────────────────────────────────────────────────────
-- `:checkhealth gerrrt` — a precise, actionable report for Core's Neovim bits that
-- otherwise fail with a generic message. The clipboard is the prime case: when no
-- backend exists, `"+y` / `"+p` surface only Neovim's opaque "clipboard provider"
-- error. Here we run the SAME `clip` / `clip-paste` ladder the provider uses and say
-- exactly what's missing and how to fix it, instead of leaving the user guessing.
--
-- This module is loaded ONLY by :checkhealth (Neovim discovers lua/**/health.lua) —
-- it is never required at startup, so it adds nothing to load time.
-- ─────────────────────────────────────────────────────────────────────────────
local M = {}

function M.check()
  local h = vim.health
  h.start("dotfiles-core: clipboard")

  local have_clip = vim.fn.executable("clip") == 1
  local have_paste = vim.fn.executable("clip-paste") == 1

  if not (have_clip and have_paste) then
    -- Core's bootstrap symlinks clip/clip-paste into ~/.local/bin; without them
    -- clipboard.lua leaves Neovim's own auto-detection in place (see its header).
    h.warn(
      ("Core's cross-OS clipboard scripts are not on PATH (clip: %s, clip-paste: %s)"):format(
        have_clip and "found" or "missing",
        have_paste and "found" or "missing"
      ),
      {
        "Neovim is using its built-in clipboard auto-detection instead.",
        "Run Core's bootstrap (it symlinks clip/clip-paste into ~/.local/bin),",
        "or add them to PATH, to get the unified WSL/macOS/Wayland/X11 provider.",
      }
    )
    return
  end

  h.ok("clip and clip-paste are on PATH")

  -- Probe a real backend by READING the clipboard (clip-paste mutates nothing). On a
  -- working box it exits 0; with no backend it exits 1 with the install hint, exactly
  -- the path that otherwise only shows up as an opaque yank/paste failure.
  local out = vim.fn.system({ "clip-paste" })
  if vim.v.shell_error == 0 then
    h.ok('a clipboard backend is reachable (clip-paste succeeded) — "+y / "+p will work')
  else
    h.error('no clipboard backend is reachable — "+y / "+p will fail', {
      "Install one for your session:",
      "  Wayland : wl-clipboard   (wl-copy / wl-paste)",
      "  X11     : xclip   or   xsel",
      "  macOS   : pbcopy/pbpaste ship with the OS",
      "  WSL     : clip.exe / powershell ship with Windows",
      vim.trim(out ~= "" and ("clip-paste said: " .. out) or ""),
    })
  end
end

return M
