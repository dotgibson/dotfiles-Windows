local M = {}

-- Diagnostic gutter signs. Written as \u{XXXX} escapes (Nerd Font codepoints) so
-- the glyphs survive copy/paste — raw private-use glyphs get silently stripped.
-- These match the statusline's diagnostic icons (lualine) for a consistent look.
local diagnostic_signs = {
	Error = "\u{f057}", -- f057 nf-fa-times_circle
	Warn = "\u{f071}", -- f071 nf-fa-exclamation_triangle
	Hint = "\u{f0eb}", -- f0eb nf-fa-lightbulb
	Info = "\u{f05a}", -- f05a nf-fa-info_circle
}

M.setup = function()
	vim.diagnostic.config({
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = diagnostic_signs.Error,
				[vim.diagnostic.severity.WARN] = diagnostic_signs.Warn,
				[vim.diagnostic.severity.INFO] = diagnostic_signs.Info,
				[vim.diagnostic.severity.HINT] = diagnostic_signs.Hint,
			},
		},
		severity_sort = true,
		float = { border = "rounded", source = true },
	})
end

return M
