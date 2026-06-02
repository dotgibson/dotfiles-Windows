-- ================================================================================================
-- TITLE : nvim-spectre | project-wide search & replace with live preview
-- LINKS : https://github.com/nvim-pack/nvim-spectre
-- ================================================================================================
return {
	"nvim-pack/nvim-spectre",
	dependencies = { "nvim-lua/plenary.nvim" },
	cmd = { "Spectre" },
	keys = {
		{
			"<leader>Sr",
			function()
				require("spectre").toggle()
			end,
			desc = "Spectre: toggle panel",
		},
		{
			"<leader>Sw",
			function()
				require("spectre").open_visual({ select_word = true })
			end,
			desc = "Spectre: search current word",
		},
		{
			"<leader>Sp",
			function()
				require("spectre").open_file_search({ select_word = true })
			end,
			desc = "Spectre: search current file",
		},
		{
			"<leader>Sc",
			mode = "v",
			function()
				require("spectre").open_visual()
			end,
			desc = "Spectre: search selection",
		},
	},
	opts = {
		open_cmd = "vnew",
		live_update = false,
		find_engine = {
			["rg"] = {
				cmd = "rg",
				args = {
					"--color=never",
					"--no-heading",
					"--with-filename",
					"--line-number",
					"--column",
					"--hidden",
					"--glob=!.git/",
				},
				options = {
					["ignore-case"] = { value = "--ignore-case", icon = "[I]", desc = "ignore case" },
					["hidden"] = { value = "--hidden", icon = "[H]", desc = "hidden files" },
				},
			},
		},
		replace_engine = {
			["sed"] = { cmd = "sed", args = nil },
		},
		default = {
			find = { cmd = "rg", options = { "ignore-case" } },
			replace = { cmd = "sed" },
		},
	},
}
