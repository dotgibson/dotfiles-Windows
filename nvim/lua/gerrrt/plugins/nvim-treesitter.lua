-- ================================================================================================
-- TITLE : nvim-treesitter (main branch — new API)
-- LINKS : https://github.com/nvim-treesitter/nvim-treesitter
-- NOTE  : Dropped lazy=false so the BufReadPost/BufNewFile event actually governs loading
--         (the two were fighting before).
-- ================================================================================================
return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	build = ":TSUpdate",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		local treesitter = require("nvim-treesitter")
		treesitter.setup({})
		local ensure_installed = {
			"bash",
			"c",
			"cpp",
			"css",
			"go",
			"html",
			"javascript",
			"json",
			"lua",
			"markdown",
			"markdown_inline",
			"python",
			"rust",
			"svelte",
			"solidity",
			"typescript",
			"vue",
			"yaml",
		}

		local config = require("nvim-treesitter.config")
		local already_installed = config.get_installed()
		local parsers_to_install = {}
		for _, parser in ipairs(ensure_installed) do
			if not vim.tbl_contains(already_installed, parser) then
				table.insert(parsers_to_install, parser)
			end
		end
		if #parsers_to_install > 0 then
			treesitter.install(parsers_to_install)
		end

		local group = vim.api.nvim_create_augroup("TreeSitterConfig", { clear = true })
		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			callback = function(args)
				if vim.list_contains(treesitter.get_installed(), vim.treesitter.language.get_lang(args.match)) then
					vim.treesitter.start(args.buf)
				end
			end,
		})
	end,
}
