-- ================================================================================================
-- TITLE : tokyonight + transparency
-- ABOUT : a clean dark theme with soft color — kept as-is, it fits the brief well.
-- LINKS : https://github.com/folke/tokyonight.nvim
-- SWAP  : prefer something else? tokyonight ships "storm" (current), "moon", "night", "day".
--         Change `style` below. Or drop in catppuccin / kanagawa / rose-pine and swap the
--         colorscheme() call.
-- ================================================================================================
return {
	{
		"xiyaowong/nvim-transparent",
		lazy = false,
		priority = 1000,
		opts = {
			extra_groups = {
				"NvimTreeNormal",
				"NvimTreeNormalNC",
				"NvimTreeSignColumn",
				"NvimTreeEndOfBuffer",
				"NvimTreeWinSeparator",
			},
		},
	},
	{
		"folke/tokyonight.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("tokyonight").setup({
				style = "storm",
				transparent = true,
				styles = { sidebars = "transparent", floats = "transparent" },
				on_highlights = function(hl, c)
					hl.Visual = { bg = c.bg_visual }
					hl.Comment = { fg = c.comment, italic = true }
				end,
			})
			vim.cmd("colorscheme tokyonight")
		end,
	},
}
