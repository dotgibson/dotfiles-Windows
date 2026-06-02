return function(capabilities)
	vim.lsp.config("yamlls", {
		capabilities = capabilities,
		settings = {
			yaml = {
				schemas = {
					["https://json.schemastore.org/composer.json"] = "composer.json",
					["https://json.schemastore.org/docker-compose.json"] = "docker-compose*.yml",
				},
				validate = true,
				format = { enable = true },
			},
		},
		filetypes = { "yaml" },
	})
end
