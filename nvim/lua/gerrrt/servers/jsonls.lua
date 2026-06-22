return function(capabilities)
	vim.lsp.config("jsonls", {
		capabilities = capabilities,
		filetypes = { "json", "jsonc" },
		-- SchemaStore (plugins/schemastore.lua) feeds the full schemastore.org catalogue so common
		-- config files (package.json, tsconfig, .eslintrc, GitHub Actions, ...) get validation +
		-- completion. Previously jsonls had none. `validate.enable` turns on the diagnostics.
		settings = {
			json = {
				schemas = require("schemastore").json.schemas(),
				validate = { enable = true },
			},
		},
	})
end
