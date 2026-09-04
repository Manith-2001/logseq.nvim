-- Isolated test/dev entry: no user config, just plenary + this repo on rtp.
-- Usage: nvim --clean -u tests/minimal_init.lua [file]
local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(repo)

-- plenary (+ telescope for the health check) installed via vim.pack (0.12)
local data = vim.fn.stdpath('data')
for _, name in ipairs({ 'plenary.nvim', 'telescope.nvim' }) do
  for _, p in ipairs({
    data .. '/site/pack/core/opt/' .. name,
    data .. '/site/pack/core/start/' .. name,
  }) do
    if vim.fn.isdirectory(p) == 1 then
      vim.opt.rtp:prepend(p)
      break
    end
  end
end

vim.g.logseq = vim.g.logseq or { graph_path = repo .. '/tests/fixtures/graph' }

-- --noplugin skips plugin/ sourcing, so load plenary's test commands explicitly.
vim.cmd('silent! runtime plugin/plenary.vim')
