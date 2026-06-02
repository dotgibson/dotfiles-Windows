-- ================================================================================================
-- TITLE : rustaceanvim | batteries-included Rust (LSP + DAP via rust-analyzer)
-- LINKS : https://github.com/mrcjkb/rustaceanvim
-- ================================================================================================
local on_attach = require("gerrrt.utils.lsp").on_attach

local config = function()
	vim.g.rustaceanvim = {
		tools = { hover_actions = { auto_focus = true } },
		server = {
			on_attach = on_attach,
			default_settings = {
				["rust-analyzer"] = { cargo = { allFeatures = true } },
			},
		},
		dap = {
			adapter = {
				type = "executable",
				command = vim.fn.exepath("lldb-dap") ~= "" and "lldb-dap"
					or vim.fn.trim(vim.fn.system("xcrun -f lldb-dap")),
				name = "rt_lldb",
			},
		},
	}
end

return {
	"mrcjkb/rustaceanvim",
	version = "^6",
	ft = "rust",
	config = config,
}
