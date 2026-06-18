-- ================================================================================================
-- TITLE : lazy.nvim Bootstrap & Plugin Setup
-- ABOUT :
--   bootstraps the 'lazy.nvim' plugin manager by cloning it if not present, prepends it to the
--   runtime path, and then loads core configuration files (globals, options, keymaps, autocmds).
--   Last, initialises 'lazy.nvim' with plugins.
-- LINKS :
--   > lazy.nvim github  : https://github.com/folke/lazy.nvim
--   > lazy.nvim website : https://lazy.folke.io/installation
-- ================================================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
---@diagnostic disable-next-line: undefined-field (fs_stat)
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

require("gerrrt.config.globals")
require("gerrrt.config.options")
require("gerrrt.config.keymaps")
require("gerrrt.config.autocmds")
require("gerrrt.config.clipboard")
require("gerrrt.config.providers")

require("lazy").setup({
	spec = {
		{ import = "gerrrt.plugins" },
	},
	install = {
		colorscheme = {
			"tokyonight",
		},
	},
	rocks = {
		enabled = false,
	},
	-- Auto-check for plugin updates, but don't spam notifications on every startup.
	-- Disabled when DOTFILES_OFFLINE=1 (engagement boxes) — the checker does background
	-- `git fetch` of plugin repos, which we don't want phoning home unattended. See globals.lua.
	checker = { enabled = not vim.g.dotfiles_offline, notify = false },
	change_detection = { notify = false },
	performance = {
		rtp = {
			-- Disable built-in runtime plugins we don't use so they're never sourced at startup.
			-- netrwPlugin is the belt-and-suspenders pair to the vim.g.loaded_netrw* globals set
			-- in config/globals.lua (nvim-tree owns file exploration). The rest — gzip/tar/zip
			-- (transparent in-place archive editing), tohtml, tutor — are unused here.
			disabled_plugins = { "netrwPlugin", "gzip", "tarPlugin", "zipPlugin", "tohtml", "tutor" },
		},
	},
})
