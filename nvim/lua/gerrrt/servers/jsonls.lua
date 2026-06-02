return function(capabilities)
	vim.lsp.config("jsonls", {
		capabilities = capabilities,
		filetypes = { "json", "jsonc" },
	})
end
