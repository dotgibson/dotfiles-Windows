-- ================================================================================================
-- TITLE : which-key | shows your keybindings as you type the leader
-- LINKS : https://github.com/folke/which-key.nvim
-- ================================================================================================
return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		spec = {
			{ "<leader>b", group = "buffer" },
			{ "<leader>c", group = "code / LSP" },
			{ "<leader>d", group = "debug (DAP)" },
			{ "<leader>f", group = "find (fzf)" },
			{ "<leader>g", group = "git" },
			{ "<leader>h", group = "harpoon" },
			{ "<leader>s", group = "split / window" },
			{ "<leader>S", group = "search & replace" },
			{ "<leader>x", group = "trouble / lists" },
			{ "<leader><tab>", group = "tabs" },
			-- non-leader: mini.surround moved here off `s` so flash owns `s` (see mini-nvim.lua)
			{ "gs", group = "surround", mode = { "n", "x" } },
		},
	},
	keys = {
		{
			"<leader>?",
			function()
				require("which-key").show({ global = false })
			end,
			desc = "Buffer Local Keymaps (which-key)",
		},
	},
}
