return function(capabilities)
	vim.lsp.config("yamlls", {
		capabilities = capabilities,
		settings = {
			yaml = {
				-- Let SchemaStore.nvim (plugins/schemastore.lua) own the catalogue instead of yamlls's
				-- built-in store, then merge in the two project-specific schemas we always want. This
				-- upgrades from two hand-listed schemas to the full schemastore set (GitHub Actions,
				-- kubernetes, gitlab-ci, renovate, ...) — schemaStore.enable=false avoids duplicating it.
				schemaStore = { enable = false, url = "" },
				schemas = vim.tbl_extend("force", require("schemastore").yaml.schemas(), {
					["https://json.schemastore.org/composer.json"] = "composer.json",
					["https://json.schemastore.org/docker-compose.json"] = "docker-compose*.yml",
				}),
				validate = true,
				format = { enable = true },
			},
		},
		filetypes = { "yaml" },
	})
end
