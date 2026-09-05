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
cmd('LogseqFollow', 'follow_link', { desc = 'Logseq: follow [[link]] under cursor' })
cmd('LogseqToday', 'today', { desc = 'Logseq: open today journal' })
cmd('LogseqNew', 'new_page', { desc = 'Logseq: new page', nargs = '?' })
cmd('LogseqGraphs', 'switch_graph', { desc = 'Logseq: switch active graph' })
cmd('LogseqGraph', 'graph_view', { desc = 'Logseq: explore page links', nargs = '?' })
cmd('LogseqTodos', 'todos', { desc = 'Logseq: list tasks (picker)' })
cmd('LogseqTodosView', 'todos_view', { desc = 'Logseq: list tasks (scratch buffer)' })
cmd('LogseqCycleTodo', 'cycle_todo', { desc = 'Logseq: cycle TODO state on current line' })
cmd(
  'LogseqSmartAction',
  'smart_action',
  { desc = 'Logseq: follow link, cycle task, or <CR> motion' }
)

-- nav_link() takes a direction string, not a command-opts table, so it
-- gets its own tiny definer with the same del-before-create idempotency.
local function navcmd(name, direction, desc)
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, function()
    require('logseq').nav_link(direction)
  end, { desc = desc })
end

navcmd('LogseqNextLink', 'next', 'Logseq: jump to next link')
navcmd('LogseqPrevLink', 'prev', 'Logseq: jump to previous link')

-- <Plug> mapping only; never steal gf/<leader> unconditionally.
-- Suggested user bind (README, M3): vim.keymap.set('n', 'gf', '<Plug>(LogseqFollow)')
if vim.fn.hasmapto('<Plug>(LogseqFollow)', 'n') == 0 then
  vim.keymap.set('n', '<Plug>(LogseqFollow)', function()
    require('logseq').follow_link()
  end, { silent = true, desc = 'Logseq: follow link under cursor' })
end
-- No default key for cycling (repo convention, plus most terminals send
-- Ctrl+Enter as plain Enter). Suggested binds (README, M8):
-- GUI: vim.keymap.set('n', '<C-CR>', '<Plug>(LogseqCycleTodo)')
if vim.fn.hasmapto('<Plug>(LogseqCycleTodo)', 'n') == 0 then
  vim.keymap.set('n', '<Plug>(LogseqCycleTodo)', function()
    require('logseq').cycle_todo()
  end, { silent = true, desc = 'Logseq: cycle TODO state on current line' })
end
-- Smart action + link navigation plugs (M9). The ftplugin maps graph
-- buffers to these; users can also bind them anywhere themselves, e.g.
-- vim.keymap.set('n', '<CR>', '<Plug>(LogseqSmartAction)', { buffer = true })
if vim.fn.hasmapto('<Plug>(LogseqSmartAction)', 'n') == 0 then
  vim.keymap.set('n', '<Plug>(LogseqSmartAction)', function()
    require('logseq').smart_action()
  end, { silent = true, desc = 'Logseq: follow link, cycle task, or move down' })
end
if vim.fn.hasmapto('<Plug>(LogseqNextLink)', 'n') == 0 then
  vim.keymap.set('n', '<Plug>(LogseqNextLink)', function()
    require('logseq').nav_link('next')
  end, { silent = true, desc = 'Logseq: jump to next link' })
end
if vim.fn.hasmapto('<Plug>(LogseqPrevLink)', 'n') == 0 then
  vim.keymap.set('n', '<Plug>(LogseqPrevLink)', function()
    require('logseq').nav_link('prev')
  end, { silent = true, desc = 'Logseq: jump to previous link' })
end
