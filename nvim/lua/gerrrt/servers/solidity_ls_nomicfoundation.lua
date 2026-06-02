return function(capabilities)
	vim.lsp.config("solidity_ls_nomicfoundation", {
		capabilities = capabilities,
		single_file_support = true,
		cmd = { "nomicfoundation-solidity-language-server", "--stdio" },
		filetypes = { "solidity" },
		settings = { rootMarkers = { ".git/" } },
	})
end
