-- ================================================================================================
-- TITLE : lualine.nvim | statusline
-- LINKS : https://github.com/nvim-lualine/lualine.nvim
-- ABOUT : A polished but restrained statusline:
--           left  : mode · git branch · git diff (+~-)
--           center: filename (relative) with modified/readonly markers
--           right : search count · attached LSP servers · diagnostics · filetype · progress · location
-- ICONS : All glyphs are written as \u{XXXX} escapes (Nerd Font private-use codepoints),
--         NOT raw glyphs. Raw glyphs get silently stripped when text passes through tools
--         that don't preserve the private-use area; escapes are plain ASCII in the file and
--         decode to the glyph at runtime, so they survive copy/paste/transfer intact.
--         Each escape is named in a trailing comment. Requires a Nerd Font in your terminal.
--         If any single glyph shows as a box (tofu), your font lacks it — swap that codepoint.
-- ================================================================================================
return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		-- Show the language servers attached to the current buffer.
		local function lsp_servers()
			local clients = vim.lsp.get_clients({ bufnr = 0 })
			if #clients == 0 then
				return ""
			end
			local names = {}
			for _, client in ipairs(clients) do
				names[#names + 1] = client.name
			end
			return "\u{f085} " .. table.concat(names, ", ") -- f085 nf-fa-cogs
		end

		require("lualine").setup({
			options = {
				theme = "tokyonight",
				icons_enabled = true,
				globalstatus = true,
				-- Powerline separators (universally present in Nerd Fonts):
				section_separators = { left = "\u{e0b0}", right = "\u{e0b2}" }, -- e0b0  / e0b2
				component_separators = { left = "\u{e0b1}", right = "\u{e0b3}" }, -- e0b1  / e0b3
				disabled_filetypes = { statusline = { "NvimTree", "neo-tree", "dapui_scopes", "dapui_breakpoints" } },
			},
			sections = {
				lualine_a = {
					{ "mode", icon = "\u{e62b}" }, -- e62b nf-custom-vim
				},
				lualine_b = {
					{ "branch", icon = "\u{e0a0}" }, -- e0a0 powerline branch
					{
						"diff",
						symbols = {
							added = "\u{f067} ", -- f067 nf-fa-plus
							modified = "\u{f111} ", -- f111 nf-fa-circle
							removed = "\u{f068} ", -- f068 nf-fa-minus
						},
					},
				},
				lualine_c = {
					{
						"filename",
						path = 1, -- relative path
						symbols = {
							modified = " \u{f111}", -- f111 nf-fa-circle (●-style "unsaved" dot)
							readonly = " \u{f023}", -- f023 nf-fa-lock
							unnamed = "[No Name]",
						},
					},
				},
				lualine_x = {
					{ "searchcount" },
					{
						lsp_servers,
						color = { gui = "italic" },
					},
					{
						"diagnostics",
						symbols = {
							error = "\u{f057} ", -- f057 nf-fa-times_circle
							warn = "\u{f071} ", -- f071 nf-fa-exclamation_triangle
							info = "\u{f05a} ", -- f05a nf-fa-info_circle
							hint = "\u{f0eb} ", -- f0eb nf-fa-lightbulb
						},
					},
					{ "filetype" },
				},
				lualine_y = {
					{ "progress" },
				},
				lualine_z = {
					{ "location", icon = "\u{e0a1}" }, -- e0a1 powerline line-number
				},
			},
			inactive_sections = {
				lualine_c = { { "filename", path = 1 } },
				lualine_x = { "location" },
			},
			extensions = { "nvim-tree", "lazy", "quickfix", "trouble", "mason" },
		})
	end,
}
