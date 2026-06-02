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
	config = function()
		require("mini.ai").setup({})
		require("mini.move").setup({})
		require("mini.surround").setup({})
		require("mini.cursorword").setup({})
		require("mini.indentscope").setup({})
		require("mini.pairs").setup({})
		require("mini.trailspace").setup({})
		require("mini.bufremove").setup({})
		require("mini.notify").setup({})
	end,
}
