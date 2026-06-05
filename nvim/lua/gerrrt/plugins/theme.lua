-- ================================================================================================
-- TITLE : tokyonight + transparency
-- ABOUT : a clean dark theme with soft color — kept as-is, it fits the brief well.
-- LINKS : https://github.com/folke/tokyonight.nvim
-- SWAP  : prefer something else? tokyonight ships "storm" (current), "moon", "night", "day".
--         Change `style` below. Or drop in catppuccin / kanagawa / rose-pine and swap the
--         colorscheme() call.
-- ================================================================================================
return {
	-- Transparency is tokyonight-native (transparent=true below). The separate
	-- xiyaowong/nvim-transparent plugin was removed as verified-redundant: under
	-- transparent=true, tokyonight already resolves NvimTreeNormal / NormalNC / SignColumn /
	-- EndOfBuffer / WinSeparator to bg=NONE (WinSeparator keeps its fg), which is exactly what
	-- nvim-transparent's extra_groups were doing. Running both was redundant and load-order
	-- fragile (two lazy=false, priority=1000 specs racing). Tradeoff: the :TransparentToggle
	-- runtime command is gone — to toggle, flip `transparent` here and reload the colorscheme.
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
