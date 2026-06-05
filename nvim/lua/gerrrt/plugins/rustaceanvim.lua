-- ================================================================================================
-- TITLE : rustaceanvim | batteries-included Rust (LSP + DAP via rust-analyzer)
-- LINKS : https://github.com/mrcjkb/rustaceanvim
-- ================================================================================================
-- NOTE: no on_attach is passed to rustaceanvim's server below. Buffer-local LSP keymaps
-- (K, gd, gr, <leader>ca, ...) are applied globally by the LspAttach autocmd in
-- config/autocmds.lua, which fires for rust-analyzer like every other server — so Rust gets
-- the same maps for free. (Passing utils/lsp.on_attach here used to be a no-op: rustaceanvim
-- calls server.on_attach with the classic (client, bufnr) signature, but that function expects
-- an LspAttach *event* table and early-returns on anything else.)
local config = function()
	vim.g.rustaceanvim = {
		tools = { hover_actions = { auto_focus = true } },
		server = {
			default_settings = {
				["rust-analyzer"] = { cargo = { allFeatures = true } },
			},
		},
		dap = {
			adapter = {
				type = "executable",
				-- Prefer lldb-dap on PATH. Only consult `xcrun -f lldb-dap` on macOS (and only if
				-- xcrun actually exists) — on Linux/Kali xcrun is absent and its error text would
				-- otherwise become the adapter command. Final fallback is the bare name so the
				-- failure is a clean "not found" rather than executing garbage.
				command = (function()
					if vim.fn.exepath("lldb-dap") ~= "" then
						return "lldb-dap"
					end
					if vim.fn.has("mac") == 1 and vim.fn.executable("xcrun") == 1 then
						local p = vim.fn.trim(vim.fn.system({ "xcrun", "-f", "lldb-dap" }))
						if vim.v.shell_error == 0 and p ~= "" then
							return p
						end
					end
					return "lldb-dap"
				end)(),
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
