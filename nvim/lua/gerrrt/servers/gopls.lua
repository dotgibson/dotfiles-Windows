return function(capabilities)
	vim.lsp.config("gopls", {
		capabilities = capabilities,
		filetypes = { "go" },
	})
end
