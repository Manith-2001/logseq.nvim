-- logseq.nvim entry point (sourced once by Neovim from plugin/).
-- Best practice: keep this file tiny. No eager require() of the plugin body;
-- every command defers to require('logseq') inside its callback (~0ms startup).
-- Idempotent: safe to :source repeatedly (deletes commands before re-creating).

local function cmd(name, fn, opts)
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, function(cmd_opts)
    require('logseq')[fn](cmd_opts)
  end, opts or {})
end

cmd('LogseqFind', 'find_files', { desc = 'Logseq: find/open pages' })
cmd('LogseqFollow', 'follow_link', { desc = 'Logseq: follow [[link]] under cursor (M2)' })
cmd('LogseqToday', 'today', { desc = 'Logseq: open today journal (M3)' })
cmd('LogseqNew', 'new_page', { desc = 'Logseq: new page (M3)', nargs = '?' })

-- <Plug> mapping only; never steal gf/<leader> unconditionally.
-- Suggested user bind (README, M3): vim.keymap.set('n', 'gf', '<Plug>(LogseqFollow)')
if vim.fn.hasmapto('<Plug>(LogseqFollow)', 'n') == 0 then
  vim.keymap.set('n', '<Plug>(LogseqFollow)', function()
    require('logseq').follow_link()
  end, { silent = true, desc = 'Logseq: follow link under cursor' })
end
