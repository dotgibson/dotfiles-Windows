-- ================================================================================================
-- TITLE : neotest | a unified, multi-language test runner
-- LINKS : https://github.com/nvim-neotest/neotest
-- ABOUT : Run the nearest test / file / suite without leaving the buffer, with pass/fail signs in
--         the gutter, an output panel, and a tree summary. Genuinely multi-language via adapters —
--         wired here for Python (neotest-python), Go (neotest-golang) and Rust (rustaceanvim's
--         built-in adapter, picked up automatically when present). nvim-nio is already in your tree
--         (nvim-dap-ui dependency), and `<leader>td` runs the nearest test under your DAP setup.
-- LAZY  : keys-only, under a new `<leader>t` (test) group — see which-key.lua. Adapters load with it.
-- ================================================================================================
return {
	"nvim-neotest/neotest",
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter",
		"nvim-neotest/neotest-python",
		"fredrikaverpil/neotest-golang",
	},
	keys = {
		{
			"<leader>tt",
			function()
				require("neotest").run.run()
			end,
			desc = "Test: nearest",
		},
		{
			"<leader>tf",
			function()
				require("neotest").run.run(vim.fn.expand("%"))
			end,
			desc = "Test: current file",
		},
		{
			"<leader>td",
			function()
				require("neotest").run.run({ strategy = "dap" })
			end,
			desc = "Test: debug nearest (DAP)",
		},
		{
			"<leader>ts",
			function()
				require("neotest").summary.toggle()
			end,
			desc = "Test: summary panel",
		},
		{
			"<leader>to",
			function()
				require("neotest").output.open({ enter = true })
			end,
			desc = "Test: show output",
		},
		{
			"<leader>tO",
			function()
				require("neotest").output_panel.toggle()
			end,
			desc = "Test: output panel",
		},
		{
			"<leader>tx",
			function()
				require("neotest").run.stop()
			end,
			desc = "Test: stop",
		},
	},
	config = function()
		local adapters = {
			require("neotest-python")({ dap = { justMyCode = false } }),
			require("neotest-golang")({}),
		}
		-- rustaceanvim ships a neotest adapter; add it only when rustaceanvim is installed.
		local ok_rust, rust_adapter = pcall(require, "rustaceanvim.neotest")
		if ok_rust then
			table.insert(adapters, rust_adapter)
		end

		require("neotest").setup({ adapters = adapters })
	end,
}
