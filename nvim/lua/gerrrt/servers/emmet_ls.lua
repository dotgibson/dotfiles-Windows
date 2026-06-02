return function(capabilities)
	vim.lsp.config("emmet_ls", {
		capabilities = capabilities,
		filetypes = {
			"typescript",
			"javascript",
			"javascriptreact",
			"typescriptreact",
			"css",
			"sass",
			"scss",
			"svelte",
			"vue",
		},
		root_dir = function(fname)
			return vim.fs.root(fname, { "package.json", ".git" })
		end,
	})
end
