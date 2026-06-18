return function(capabilities)
	vim.lsp.config("ts_ls", {
		capabilities = capabilities,
		filetypes = { "typescript", "javascript", "typescriptreact", "javascriptreact" },
		settings = { typescript = { indentStyle = "space", indentSize = 2 } },
		-- Native vim.lsp.config uses `root_markers` (a list), NOT the old lspconfig
		-- `root_dir = function(fname)` form. Under native LSP a root_dir FUNCTION has the
		-- signature fun(bufnr, on_dir) and must CALL on_dir() to start the client — a
		-- function that merely returns a path (the lspconfig idiom) is silently ignored,
		-- so the server never attaches. root_markers is the correct native equivalent.
		root_markers = { "tsconfig.json", "jsconfig.json", "package.json" },
	})
end
