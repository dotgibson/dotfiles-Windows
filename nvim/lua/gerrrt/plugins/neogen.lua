-- ================================================================================================
-- TITLE : neogen | generate annotations / docstrings from the symbol under the cursor
-- LINKS : https://github.com/danymat/neogen
-- ABOUT : Put the cursor on a function/class and `<leader>cn` writes the doc skeleton in that
--         language's convention — LuaCATS for Lua, docstrings for Python, JSDoc for TS/JS, godoc
--         for Go, Doxygen for C/C++. Genuinely multi-language (it reads treesitter, which you
--         already run) and it understands LuaSnip placeholders, so it tab-jumps through fields
--         using your existing blink.cmp snippet engine.
-- LAZY  : cmd + keys. Sits under your `<leader>c` (code) group next to code-action/format.
-- ================================================================================================
return {
	"danymat/neogen",
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	cmd = "Neogen",
	keys = {
		{
			"<leader>cn",
			function()
				require("neogen").generate()
			end,
			desc = "Generate annotation / docstring",
		},
	},
	opts = {
		snippet_engine = "luasnip", -- reuse the engine blink.cmp already drives
		languages = {
			python = { template = { annotation_convention = "google_docstrings" } },
			typescript = { template = { annotation_convention = "jsdoc" } },
			typescriptreact = { template = { annotation_convention = "jsdoc" } },
			javascript = { template = { annotation_convention = "jsdoc" } },
		},
	},
}
