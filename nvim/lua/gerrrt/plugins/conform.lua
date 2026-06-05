-- ================================================================================================
-- TITLE : conform.nvim | formatter runner
-- LINKS : https://github.com/stevearc/conform.nvim
-- ABOUT : Maps filetypes to formatters and runs them. Format-on-save is wired in
--         config/autocmds.lua (trailing whitespace trimmed first); <leader>cf formats on demand.
-- ASTRAL: Python formatting uses ruff (format + import-sort). ruff + ty are installed via uv
--         (the Astral way), NOT mason — run once:
--             uv tool install ruff
--             uv tool install ty
--         mason-tool-installer below covers the NON-Python tools. Prefer mason for ruff? add
--         "ruff" back to ensure_installed.
-- ================================================================================================
return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	dependencies = {
		{ "WhoIsSethDaniel/mason-tool-installer.nvim", dependencies = { "mason-org/mason.nvim" } },
	},
	keys = {
		{
			"<leader>cf",
			function()
				require("conform").format({ async = true, lsp_format = "fallback" })
			end,
			mode = { "n", "v" },
			desc = "Format buffer / range",
		},
	},
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
			python = { "ruff_format", "ruff_organize_imports" },
			sh = { "shfmt" },
			bash = { "shfmt" },
			go = { "gofumpt" },
			c = { "clang_format" },
			cpp = { "clang_format" },
			json = { "prettierd" },
			jsonc = { "prettierd" },
			css = { "prettierd" },
			html = { "prettierd" },
			markdown = { "prettierd" },
			yaml = { "prettierd" },
			javascript = { "prettierd" },
			javascriptreact = { "prettierd" },
			typescript = { "prettierd" },
			typescriptreact = { "prettierd" },
			svelte = { "prettierd" },
			vue = { "prettierd" },
			-- NOTE: zsh is intentionally absent. shfmt is a POSIX/bash/mksh formatter and does
			-- NOT understand zsh — it mangles zsh-only syntax (glob qualifiers (#qN), ${(%):-%x},
			-- $+widgets[name-with-hyphens], &|, ...). There is no safe zsh formatter, so zsh files
			-- are never auto-formatted. (autocmds.lua also hard-skips formatting for ft=zsh, and
			-- utils/lsp.lua disables bashls's LSP formatting so the "fallback" path can't shfmt it.)
		},
	},
	config = function(_, opts)
		require("conform").setup(opts)

		-- Mason installs the NON-Python CLI tools. ruff/ty come from uv (see header).
		require("mason-tool-installer").setup({
			ensure_installed = {
				-- formatters (conform)
				"stylua",
				"shfmt",
				"gofumpt",
				"clang-format",
				"prettierd",
				-- linters (nvim-lint)
				"shellcheck",
				"revive",
				"eslint_d",
				"hadolint",
				"cpplint",
				"luacheck",
				"solhint",
			},
			-- Skip the startup install/update pass on engagement boxes (DOTFILES_OFFLINE=1),
			-- which would otherwise hit the mason registry and download tools. See globals.lua.
			run_on_start = not vim.g.dotfiles_offline,
		})
	end,
}
