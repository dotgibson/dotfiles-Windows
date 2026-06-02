-- ================================================================================================
-- TITLE : fzf-lua | fuzzy finder
-- LINKS : https://github.com/ibhagwan/fzf-lua
-- NOTE  : LSP-specific pickers (definitions/refs/symbols) live in utils/lsp.lua on_attach,
--         so they're buffer-local and only active when a server is attached. This file
--         keeps the general finders.
-- ================================================================================================
return {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	cmd = "FzfLua",
	keys = {
		{
			"<leader>ff",
			function()
				require("fzf-lua").files()
			end,
			desc = "FZF Files",
		},
		{
			"<leader>fg",
			function()
				require("fzf-lua").live_grep()
			end,
			desc = "FZF Live Grep",
		},
		{
			"<leader>fb",
			function()
				require("fzf-lua").buffers()
			end,
			desc = "FZF Buffers",
		},
		{
			"<leader>fh",
			function()
				require("fzf-lua").help_tags()
			end,
			desc = "FZF Help Tags",
		},
		{
			"<leader>fr",
			function()
				require("fzf-lua").oldfiles()
			end,
			desc = "FZF Recent Files",
		},
		{
			"<leader>fk",
			function()
				require("fzf-lua").keymaps()
			end,
			desc = "FZF Keymaps",
		},
		{
			"<leader>fx",
			function()
				require("fzf-lua").diagnostics_document()
			end,
			desc = "FZF Diagnostics (doc)",
		},
		{
			"<leader>fX",
			function()
				require("fzf-lua").diagnostics_workspace()
			end,
			desc = "FZF Diagnostics (workspace)",
		},
	},
	opts = {},
}
