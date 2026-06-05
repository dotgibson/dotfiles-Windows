-- ================================================================================================
-- TITLE : nvim-lint | standalone linter runner
-- LINKS : https://github.com/mfussenegger/nvim-lint
-- ABOUT : Runs a filetype's linter on write / leaving insert mode, surfacing results as
--         normal diagnostics (Trouble, <leader>cd, [d/]d all work). Binaries installed by
--         mason-tool-installer in conform.lua.
-- ASTRAL: Python is intentionally NOT here — the ruff language server (servers/ruff.lua)
--         provides Python lint diagnostics AND code actions. Listing ruff here too would
--         double-report.
-- ================================================================================================
return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = {
			lua = { "luacheck" },
			sh = { "shellcheck" },
			bash = { "shellcheck" },
			go = { "revive" },
			c = { "cpplint" },
			cpp = { "cpplint" },
			javascript = { "eslint_d" },
			javascriptreact = { "eslint_d" },
			typescript = { "eslint_d" },
			typescriptreact = { "eslint_d" },
			svelte = { "eslint_d" },
			vue = { "eslint_d" },
			dockerfile = { "hadolint" },
			solidity = { "solhint" },
			-- NOTE: no zsh entry. shellcheck only supports sh/bash/dash/ksh and emits SC1071
			-- ("ShellCheck only supports sh/bash/dash/ksh scripts") on a zsh file — i.e. a useless
			-- error diagnostic on every zsh buffer. Nothing reliably lints zsh, so we don't.
		}

		local grp = vim.api.nvim_create_augroup("NvimLint", { clear = true })
		vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
			group = grp,
			callback = function()
				require("lint").try_lint()
			end,
		})
	end,
}
