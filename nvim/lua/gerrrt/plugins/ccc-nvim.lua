-- ================================================================================================
-- TITLE : ccc.nvim  | colour picker & highlighter
-- LINKS : https://github.com/uga-rosa/ccc.nvim
-- ================================================================================================
return {
	"uga-rosa/ccc.nvim",
	ft = { "css", "scss", "sass", "less", "html", "javascript", "javascriptreact", "typescript", "typescriptreact", "svelte", "vue" },
	cmd = { "CccPick", "CccConvert", "CccHighlighterToggle" },
	config = function()
		require("ccc").setup({
			highlighter = { auto_enable = true, lsp = true },
			highlight_mode = "virtual",
		})
	end,
}
