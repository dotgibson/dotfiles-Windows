return function(capabilities)
	vim.lsp.config("tailwindcss", {
		capabilities = capabilities,
		filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" },
		root_dir = function(fname)
			return vim.fs.root(fname, {
				"tailwind.config.js",
				"tailwind.config.ts",
				"tailwind.config.mjs",
				"postcss.config.js",
				"postcss.config.ts",
			})
		end,
	})
end
