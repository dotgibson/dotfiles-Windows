-- ================================================================================================
-- TITLE : taplo (TOML language server) LSP Setup
-- LINKS : https://github.com/tamasfe/taplo  ·  https://taplo.tamasfe.dev/
-- ABOUT : Completion, validation, hover and formatting for TOML — which is everywhere in your
--         stack: pyproject.toml (ruff/ty), Cargo.toml (rust), foundry.toml (solidity), plus
--         starship/mise configs in this very dotfiles repo. Schema-aware via SchemaStore.
-- INSTALL: mason — package name "taplo" (added to ensure_installed in plugins/conform.lua).
-- ================================================================================================
return function(capabilities)
	vim.lsp.config("taplo", {
		capabilities = capabilities,
		cmd = { "taplo", "lsp", "stdio" },
		filetypes = { "toml" },
		root_markers = { "*.toml", ".git" },
	})
end
