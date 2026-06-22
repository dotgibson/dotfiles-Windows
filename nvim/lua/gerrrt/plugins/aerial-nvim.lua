-- ================================================================================================
-- TITLE : aerial.nvim | a persistent symbol outline sidebar
-- LINKS : https://github.com/stevearc/aerial.nvim
-- ABOUT : dropbar (breadcrumbs) tells you WHERE you are; Trouble symbols and fzf-lua document
--         symbols are momentary pickers. aerial is the missing third: a docked, always-current
--         outline of the file's structure you can keep open and click/scroll through — invaluable
--         in large multi-language files. Sources from the LSP document symbols you already get on
--         attach, with a treesitter fallback, so it needs nothing new.
-- LAZY  : cmd + a single `<leader>co` toggle under your `<leader>c` (code) group.
-- ================================================================================================
return {
	"stevearc/aerial.nvim",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-tree/nvim-web-devicons",
	},
	cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
	keys = {
		{ "<leader>co", "<cmd>AerialToggle!<cr>", desc = "Code outline (Aerial)" },
	},
	opts = {
		backends = { "lsp", "treesitter", "markdown", "man" },
		layout = { default_direction = "right", min_width = 28 },
		show_guides = true,
		-- jump through symbols with { and } when the outline has focus
		keymaps = {
			["{"] = "actions.prev",
			["}"] = "actions.next",
		},
	},
}
