return function(capabilities)
	vim.lsp.config("ts_ls", {
		capabilities = capabilities,
		filetypes = { "typescript", "javascript", "typescriptreact", "javascriptreact" },
		settings = { typescript = { indentStyle = "space", indentSize = 2 } },
		root_dir = function(fname)
			return vim.fs.root(fname, { "tsconfig.json", "jsconfig.json", "package.json" })
		end,
	})
end
