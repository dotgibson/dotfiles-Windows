-- ================================================================================================
-- TITLE : mini.nvim modules | small, focused editing upgrades
-- LINKS : https://github.com/echasnovski/mini.nvim
-- NOTE  : Removed mini.comment (Neovim ships native gc/gcc since 0.10).
--         Consolidated from separate per-module specs into a single spec so lazy.nvim only
--         tracks one plugin entry and runtime/lockfile overhead is minimized.
--         mini.move owns <A-h/j/k/l> line moving; mini.bufremove backs <leader>bd.
-- ================================================================================================
return {
	"echasnovski/mini.nvim",
	version = "*",
	-- Deferred off the startup critical path: none of these modules are needed before the
	-- first UI paint. mini.notify only has to replace vim.notify before the first toast, and
	-- mini.trailspace.trim() only runs in the BufWritePre autocmd (config/autocmds.lua) — both
	-- fire well after VeryLazy. ai/move/surround/pairs are ready before you can edit a buffer.
	event = "VeryLazy",
	config = function()
		require("mini.ai").setup({})
		require("mini.move").setup({})
		-- mini.surround on the `gs` prefix (gsa/gsd/gsr/gsf/gsF/gsh/gsn) instead of the default
		-- `s*`. flash.nvim owns `s` (jump); with surround also living on `s*`, every `s` press had
		-- to wait out `timeoutlen` (500ms) to disambiguate `s` from `sa`/`sd`/`sr`/... Moving
		-- surround to `gs` frees `s` to fire flash instantly. (`gs` only shadows the near-useless
		-- `:sleep` default — swap to a `gz` prefix if you ever want plain `gs` back.)
		require("mini.surround").setup({
			mappings = {
				add = "gsa", -- add surround (normal: gsaiw" ; visual: select then gsa")
				delete = "gsd", -- delete surround (gsd")
				replace = "gsr", -- replace surround (gsr"' )
				find = "gsf", -- find surround to the right
				find_left = "gsF", -- find surround to the left
				highlight = "gsh", -- highlight surround
				update_n_lines = "gsn", -- update n_lines used for search
			},
		})
		require("mini.cursorword").setup({})
		require("mini.indentscope").setup({})
		require("mini.pairs").setup({})
		require("mini.trailspace").setup({})
		require("mini.bufremove").setup({})
		require("mini.notify").setup({})
		-- setup() alone does NOT replace vim.notify — without this line mini.notify is configured
		-- but unused, and vim.notify(...) calls (e.g. harpoon's "added" toast) still hit Neovim's
		-- built-in notifier. make_notify() returns a drop-in replacement. (No competing notifier
		-- like noice/fidget is installed, so there's nothing to clash with.)
		vim.notify = require("mini.notify").make_notify()
	end,
}
