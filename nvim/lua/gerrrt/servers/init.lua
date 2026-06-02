-- LSP client capabilities now come from blink.cmp (was: cmp_nvim_lsp). blink
-- advertises the completion capabilities its sources support; get_lsp_capabilities
-- merges them onto Neovim's defaults. (Migration: see plugins/blink-cmp.lua.)
local capabilities = require("blink.cmp").get_lsp_capabilities()

-- Language Server Protocol (LSP)
require("gerrrt.servers.lua_ls")(capabilities)
require("gerrrt.servers.ty")(capabilities) -- Astral: Python type checking + language features
require("gerrrt.servers.ruff")(capabilities) -- Astral: Python lint diagnostics + code actions
require("gerrrt.servers.gopls")(capabilities)
require("gerrrt.servers.jsonls")(capabilities)
require("gerrrt.servers.ts_ls")(capabilities)
require("gerrrt.servers.bashls")(capabilities)
require("gerrrt.servers.clangd")(capabilities)
require("gerrrt.servers.dockerls")(capabilities)
require("gerrrt.servers.emmet_ls")(capabilities)
require("gerrrt.servers.yamlls")(capabilities)
require("gerrrt.servers.tailwindcss")(capabilities)
require("gerrrt.servers.solidity_ls_nomicfoundation")(capabilities)

-- Python: ty (types) + ruff (lint/codeactions) is the Astral stack — pyright intentionally
-- not enabled. To fall back to pyright, re-add servers/pyright.lua and list it here.

vim.lsp.enable({
	"lua_ls",
	"ty",
	"ruff",
	"gopls",
	"jsonls",
	"ts_ls",
	"bashls",
	"clangd",
	"dockerls",
	"emmet_ls",
	"yamlls",
	"tailwindcss",
	"solidity_ls_nomicfoundation",
})
