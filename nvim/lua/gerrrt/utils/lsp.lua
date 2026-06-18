-- ================================================================================================
-- TITLE : LSP on_attach
-- ABOUT : buffer-local keymaps bound whenever a language server attaches.
-- NOTE  : Neovim 0.12 ships capable native LSP, so this uses vim.lsp.buf.* directly
--         (hover / rename / code action / signature) and fzf-lua for the picker-style
--         lookups (definitions / references / symbols). lspsaga was removed — it only
--         duplicated what's now built in. DAP keymaps live in the nvim-dap plugin spec,
--         not here, so they aren't gated behind an LSP attach.
-- ================================================================================================
local M = {}

M.on_attach = function(event)
	if not event.data then
		return
	end

	local ok, client = pcall(vim.lsp.get_client_by_id, event.data.client_id)
	if not ok or not client then
		return
	end

	local bufnr = event.buf
	-- Astral: let ty own hover on Python; ruff's hover is minimal and would clash.
	if client.name == "ruff" then
		client.server_capabilities.hoverProvider = false
	end

	-- bash-language-server formats by shelling out to shfmt, which mangles zsh. We attach
	-- bashls to zsh files for completion, but must NOT let it format them — otherwise the
	-- conform lsp_format="fallback" path (and <leader>cf) would re-introduce the corruption
	-- we removed from conform. sh/bash are unaffected: conform formats those with shfmt
	-- directly, so the LSP fallback never runs for them anyway.
	if client.name == "bashls" then
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end

	-- Neovim 0.11+/0.12 ships default LSP maps grn/gra/grr/gri. Our `gr`=references
	-- below is a *complete* mapping, so leaving these in place makes `gr` wait
	-- timeoutlen (500ms) before firing. We have <leader>rn / <leader>ca / gr / gi
	-- for these already, so clear the defaults to make `gr` instant.
	for _, lhs in ipairs({ "grn", "gra", "grr", "gri" }) do
		pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
	end

	local keymap = vim.keymap.set
	local function opts(desc)
		return { noremap = true, silent = true, buffer = bufnr, desc = desc }
	end

	-- ── Native LSP (built into Neovim 0.12) ──────────────────────────────────
	keymap("n", "K", vim.lsp.buf.hover, opts("Hover documentation"))
	keymap("n", "gD", vim.lsp.buf.declaration, opts("Go to declaration"))
	keymap("n", "<leader>rn", vim.lsp.buf.rename, opts("Rename symbol"))
	keymap({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts("Code action"))
	keymap("i", "<C-s>", vim.lsp.buf.signature_help, opts("Signature help"))

	-- ── Diagnostics (native) ─────────────────────────────────────────────────
	keymap("n", "<leader>cd", vim.diagnostic.open_float, opts("Line diagnostics"))
	keymap("n", "[d", function()
		vim.diagnostic.jump({ count = -1, float = true })
	end, opts("Previous diagnostic"))
	keymap("n", "]d", function()
		vim.diagnostic.jump({ count = 1, float = true })
	end, opts("Next diagnostic"))

	-- ── fzf-lua pickers (nice fuzzy UI for the list-style lookups) ───────────
	keymap("n", "gd", "<cmd>FzfLua lsp_definitions<CR>", opts("Definitions"))
	keymap("n", "gr", "<cmd>FzfLua lsp_references<CR>", opts("References"))
	keymap("n", "gi", "<cmd>FzfLua lsp_implementations<CR>", opts("Implementations"))
	keymap("n", "gy", "<cmd>FzfLua lsp_typedefs<CR>", opts("Type definitions"))
	keymap("n", "<leader>fs", "<cmd>FzfLua lsp_document_symbols<CR>", opts("Document symbols"))
	keymap("n", "<leader>fw", "<cmd>FzfLua lsp_workspace_symbols<CR>", opts("Workspace symbols"))

	-- ── Organize imports (if the server supports it) ─────────────────────────
	if client:supports_method("textDocument/codeAction", bufnr) then
		keymap("n", "<leader>oi", function()
			vim.lsp.buf.code_action({
				context = { only = { "source.organizeImports" }, diagnostics = {} },
				apply = true,
			})
			vim.defer_fn(function()
				vim.lsp.buf.format({ bufnr = bufnr })
			end, 50)
		end, opts("Organize imports"))
	end
end

return M
