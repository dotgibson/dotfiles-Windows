return function(capabilities)
	vim.lsp.config("clangd", {
		capabilities = capabilities,
		cmd = { "clangd", "--offset-encoding=utf-16" },
		filetypes = { "c", "cpp" },
	})
end
