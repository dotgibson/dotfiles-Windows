-- ================================================================================================
-- TITLE : incline.nvim | floating per-window filename labels
-- LINKS : https://github.com/b0o/incline.nvim
-- ABOUT : You run globalstatus=true (one lualine for the whole UI) and a split-heavy workflow
--         (vim-tmux-navigator, <leader>sv/sh). The tradeoff of a global statusline is you can't tell
--         at a glance WHICH split holds WHICH file. incline draws a small, unobtrusive floating
--         label in the top-right corner of every window with the filename + a modified marker — the
--         missing per-window identity, without giving up your single global statusline.
-- LAZY  : event = BufReadPost/BufNewFile. Honors your transparency (winblend/tokyonight). The
--         modified-dot glyph is a \u{XXXX} escape (Nerd Font codepoint) so it survives transfer,
--         matching the house convention in lualine.lua / diagnostics.lua.
-- ================================================================================================
return {
	"b0o/incline.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

		require("incline").setup({
			window = {
				margin = { vertical = 0, horizontal = 1 },
				padding = 1,
				placement = { horizontal = "right", vertical = "top" },
			},
			render = function(props)
				local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
				if fname == "" then
					fname = "[No Name]"
				end
				local modified = vim.bo[props.buf].modified

				local parts = {}
				if devicons_ok then
					local icon, color = devicons.get_icon_color(fname, nil, { default = true })
					parts[#parts + 1] = { icon .. " ", guifg = color }
				end
				parts[#parts + 1] = { fname, gui = modified and "bold,italic" or "None" }
				if modified then
					parts[#parts + 1] = { " \u{f111}", guifg = "#e0af68" } -- f111 nf-fa-circle (unsaved dot)
				end
				return parts
			end,
		})
	end,
}
