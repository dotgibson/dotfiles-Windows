-- nvim/lua/gerrrt/config/providers.lua
-- ─────────────────────────────────────────────────────────────────────────────
-- Disable the language "providers" you don't use. Neovim's perl/ruby/node/python
-- providers exist only for a small set of legacy remote plugins; disabling an
-- unused one is the CORRECT, intentional way to clear its :checkhealth warning —
-- not a workaround. It also makes startup marginally faster (no probe spawn).
-- ─────────────────────────────────────────────────────────────────────────────

vim.g.loaded_perl_provider = 0 -- almost never needed
vim.g.loaded_ruby_provider = 0 -- enable only if some plugin actually needs ruby

-- Node + Python providers are LEFT ENABLED on purpose — a few plugins use them,
-- and the install notes get them healthy. If you later decide you don't need
-- one, disable it the same way:
-- vim.g.loaded_node_provider    = 0
-- vim.g.loaded_python3_provider = 0
