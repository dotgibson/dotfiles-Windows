-- nvim/lua/gerrrt/config/clipboard.lua
-- ─────────────────────────────────────────────────────────────────────────────
-- Cross-OS system-clipboard provider for Neovim.
--
-- Routes the "+ and "* registers through Core's `clip` / `clip-paste` scripts,
-- which themselves detect WSL / macOS / Wayland / X11. This is what makes
-- `"+y` (yank to system clipboard) and `"+p` (paste from it) work identically on
-- every machine — most importantly on WSL, where Neovim otherwise has NO native
-- clipboard provider and `"+y` silently does nothing.
--
-- Requires `clip` and `clip-paste` on PATH (bootstrap.sh symlinks them into
-- ~/.local/bin). If they're missing, we leave Neovim's own auto-detection alone
-- so nothing breaks on a box that hasn't been bootstrapped.
--
-- NOTE: This is an OPT-IN setup. Yanks/deletes stay in Neovim's own registers
-- by default; you reach the system clipboard explicitly with the "+ register
-- (e.g. "+yy / "+p). That's why options.lua does NOT set clipboard=unnamedplus —
-- the two were contradicting each other before. This keeps `<leader>p`
-- (paste-without-yank) and the black-hole register behaving as intended.
-- ─────────────────────────────────────────────────────────────────────────────

if vim.fn.executable("clip") == 1 and vim.fn.executable("clip-paste") == 1 then
  vim.g.clipboard = {
    name = "clip-crossos",
    copy = {
      ["+"] = "clip",
      ["*"] = "clip",
    },
    paste = {
      ["+"] = "clip-paste",
      ["*"] = "clip-paste",
    },
    -- cache_enabled = 0 on purpose: every "+p reflects the LIVE system clipboard
    -- (including copies made in other apps), never a stale value nvim cached. That
    -- means nvim re-execs clip-paste per access, so the scripts themselves are kept
    -- fork-light — their WSL probe reads /proc/version with a bash builtin instead
    -- of forking grep each time (see bin/clip). Correctness kept, waste removed.
    cache_enabled = 0,
  }
elseif vim.fn.executable("clip.exe") == 1 then
  -- Windows-native fallback (psmux / no Core bootstrap)
  local pwsh = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
  vim.g.clipboard = {
    name = "clip-windows",
    copy = {
      ["+"] = "clip.exe",
      ["*"] = "clip.exe",
    },
    paste = {
      ["+"] = { pwsh, "-NoProfile", "-Command", "Get-Clipboard" },
      ["*"] = { pwsh, "-NoProfile", "-Command", "Get-Clipboard" },
    },
    cache_enabled = 0,
  }
end
