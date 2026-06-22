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
			toml = { "taplo" }, -- taplo formats TOML; the same binary also serves as its LSP (servers/taplo.lua)
			-- NOTE: zsh is intentionally absent. shfmt is a POSIX/bash/mksh formatter and does
			-- NOT understand zsh — it mangles zsh-only syntax (glob qualifiers (#qN), ${(%):-%x},
			-- $+widgets[name-with-hyphens], &|, ...). There is no safe zsh formatter, so zsh files
			-- are never auto-formatted. (autocmds.lua also hard-skips formatting for ft=zsh, and
			-- utils/lsp.lua disables bashls's LSP formatting so the "fallback" path can't shfmt it.)
		},
	},
	config = function(_, opts)
		require("conform").setup(opts)

		-- One Mason manifest for EVERYTHING Mason owns: LSP servers, formatters, linters.
		-- This is the central install pass — previously only formatters/linters were listed, so the
		-- 11 servers enabled in servers/init.lua relied on their binaries already being on PATH
		-- (`vim.lsp.enable` fails silently when a server binary is missing). Listing the servers
		-- here closes that gap: a fresh machine ends up with a working LSP stack after one start.
		--
		-- DELIBERATELY NOT here (installed by other channels — listing them would double-install):
		--   • ruff, ty .......... uv tool install (Astral; see header + servers/ruff.lua, ty.lua)
		--   • rust-analyzer ..... rustaceanvim / rustup (plugins/rustaceanvim.lua)
		--   • debugpy, codelldb . mason-nvim-dap (plugins/nvim-dap-ui.lua)
		--   • nomicfoundation-solidity-language-server — npm i -g @nomicfoundation/solidity-language-server
		--     (not carried in the Mason registry under a stable name; servers/solidity_*.lua expects
		--      the binary on PATH). solhint (its linter) IS mason-managed, below.
		require("mason-tool-installer").setup({
			ensure_installed = {
				-- ── LSP servers (mason package names; enabled in servers/init.lua) ──────────
				"lua-language-server",
				"gopls",
				"json-lsp",
				"typescript-language-server",
				"bash-language-server",
				"clangd",
				"dockerfile-language-server",
				"emmet-ls",
				"yaml-language-server",
				"tailwindcss-language-server",
				"taplo", -- TOML (also the conform formatter for toml)
				"marksman", -- Markdown
				"html-lsp", -- HTML validation
				"css-lsp", -- CSS/SCSS/LESS validation
				"svelte-language-server", -- Svelte component LSP (you already format/lint svelte)
				"vue-language-server", -- Vue/Volar LSP (also ships @vue/typescript-plugin for ts_ls)
				-- ── formatters (conform) ───────────────────────────────────────────────────
				"stylua",
				"shfmt",
				"gofumpt",
				"clang-format",
				"prettierd",
				-- ── linters (nvim-lint) ────────────────────────────────────────────────────
				"shellcheck",
				"golangci-lint", -- Go meta-linter (supersedes revive; richer diagnostics)
				"eslint_d",
				"hadolint",
				"cpplint",
				"luacheck",
				"solhint",
				"stylelint", -- CSS/SCSS/LESS lint (only runs when a project stylelint config exists)
				"markdownlint-cli2", -- markdown lint (mirrors the repo's markdown gate)
				"yamllint", -- yaml lint
			},
			-- Skip the startup install/update pass on engagement boxes (DOTFILES_OFFLINE=1),
			-- which would otherwise hit the mason registry and download tools. See globals.lua.
			run_on_start = not vim.g.dotfiles_offline,
		})
	end,
}
