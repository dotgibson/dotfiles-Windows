return function(capabilities)
	vim.lsp.config("dockerls", {
		capabilities = capabilities,
		filetypes = { "dockerfile" },
		cmd = { "docker-langserver", "--stdio" },
		root_dir = require("lspconfig").util.root_pattern("Dockerfile"),
	})
end
