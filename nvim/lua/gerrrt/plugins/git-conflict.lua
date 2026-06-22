-- ================================================================================================
-- TITLE : git-conflict.nvim | resolve merge/rebase conflicts in-place
-- LINKS : https://github.com/akinsho/git-conflict.nvim
-- ABOUT : Highlights conflict regions (ours/theirs/ancestor) right in the buffer and lets you pick
--         a side with one keystroke. diffview's merge_tool (diffview-nvim.lua) is the full-window
--         3-way resolver; this is the lightweight inline path for the common 2-or-3 marker conflict
--         you hit mid-rebase — no need to open a separate review surface.
-- KEYMAPS: `default_mappings = false` is deliberate — the plugin's defaults bind `co`/`ct`/`cb`,
--          which would shadow the everyday `ct{char}` (change-till) operator. We rebind the choices
--          under `<leader>gx` (git group, free prefix) and conflict navigation to `]x`/`[x`.
-- LAZY  : event = BufReadPost/BufNewFile so markers are detected as soon as a file opens.
-- ================================================================================================
return {
	"akinsho/git-conflict.nvim",
	version = "*",
	event = { "BufReadPost", "BufNewFile" },
	opts = {
		default_mappings = false,
		disable_diagnostics = false,
	},
	keys = {
		{ "]x", "<cmd>GitConflictNextConflict<cr>", desc = "Next git conflict" },
		{ "[x", "<cmd>GitConflictPrevConflict<cr>", desc = "Prev git conflict" },
		{ "<leader>gxo", "<cmd>GitConflictChooseOurs<cr>", desc = "Conflict: choose ours" },
		{ "<leader>gxt", "<cmd>GitConflictChooseTheirs<cr>", desc = "Conflict: choose theirs" },
		{ "<leader>gxb", "<cmd>GitConflictChooseBoth<cr>", desc = "Conflict: choose both" },
		{ "<leader>gx0", "<cmd>GitConflictChooseNone<cr>", desc = "Conflict: choose none" },
		{ "<leader>gxl", "<cmd>GitConflictListQf<cr>", desc = "Conflict: list (quickfix)" },
	},
}
