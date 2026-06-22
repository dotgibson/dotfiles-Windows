-- ================================================================================================
-- TITLE : vim-dadbod (+ ui +completion) | a database client inside Neovim
-- LINKS : https://github.com/tpope/vim-dadbod
--         https://github.com/kristijanhusak/vim-dadbod-ui
--         https://github.com/kristijanhusak/vim-dadbod-completion
-- ABOUT : The one editing capability the rest of this config didn't cover. dadbod runs queries
--         against live connections (postgres/mysql/sqlite/redis/…); dadbod-ui is the drawer on
--         `<leader>uD` that lists connections, lets you browse schemas/tables, and saves queries.
--         Pairs with your existing DAP/neotest/LSP flow so a DB round-trip never leaves the editor.
-- LAZY  : on the DBUI* commands + the SQL filetypes only — zero startup cost. Connections come
--         from $DBUI_URL / the `g:dbs` table / a saved-queries dir; nothing is hard-coded here, so
--         this is safe to vendor to every OS repo (no machine-specific connection strings).
-- COMPLETION: wired engine-agnostically via buffer-local `omnifunc` (<C-x><C-o>) so it works
--         regardless of blink.cmp. To fold it INTO the blink menu instead, add `saghen/blink.compat`
--         and register `vim-dadbod-completion` as a compat source for ft={sql,mysql,plsql}.
-- ================================================================================================
return {
	"kristijanhusak/vim-dadbod-ui",
	dependencies = {
		{ "tpope/vim-dadbod", lazy = true },
		{ "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
	},
	cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
	keys = {
		{ "<leader>uD", "<cmd>DBUIToggle<cr>", desc = "Toggle Database UI (dadbod)" },
		{ "<leader>uF", "<cmd>DBUIFindBuffer<cr>", desc = "Find DB query buffer" },
	},
	init = function()
		-- dadbod-ui is configured through globals (it has no setup() function).
		vim.g.db_ui_use_nerd_fonts = 1
		vim.g.db_ui_win_position = "left"
		vim.g.db_ui_execute_on_save = 0 -- never run a query just because you :w — explicit only
		vim.g.db_ui_show_database_icon = 1

		-- Buffer-local omni completion for SQL dialects (engine-agnostic; see COMPLETION note).
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("DadbodCompletion", { clear = true }),
			pattern = { "sql", "mysql", "plsql" },
			callback = function()
				vim.bo.omnifunc = "vim_dadbod_completion#omni"
			end,
		})
	end,
}
