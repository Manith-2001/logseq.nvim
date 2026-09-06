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
cmd('LogseqSwitchGraph', 'switch_graph', { desc = 'Logseq: switch active graph' })
cmd('LogseqGraph', 'graph_view', { desc = 'Logseq: explore page links', nargs = '?' })
cmd('LogseqGraphAll', 'graph_view_all', { desc = 'Logseq: overview of the whole graph' })
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

-- [[ ]] completion cache (M10.2): dangling titles are cached per root
-- and rebuilt lazily, so any markdown write or directory change drops
-- the cache. Idempotent via clear=true (safe to :source repeatedly).
local complete_cache_grp = vim.api.nvim_create_augroup('LogseqCompleteCache', { clear = true })
-- Named `on_event` (not `...cmd`): the docs inventory spec extracts user
-- commands from this file with `n?cmd%('name'`, which would otherwise also
-- match these autocmd event names.
local on_event = vim.api.nvim_create_autocmd
on_event('BufWritePost', {
  group = complete_cache_grp,
  pattern = '*.md',
  desc = 'Logseq: invalidate [[ ]] completion cache',
  callback = function()
    require('logseq.complete').invalidate()
  end,
})
on_event('DirChanged', {
  group = complete_cache_grp,
  desc = 'Logseq: invalidate [[ ]] completion cache',
  callback = function()
    require('logseq.complete').invalidate()
  end,
})

-- <Plug> mapping only; never steal gf/<leader> unconditionally.
-- Suggested user bind (README, M3): vim.keymap.set('n', 'gf', '<Plug>(LogseqFollow)')
-- API-01: guard on the exact <Plug> left-hand side (maparg), never on
-- hasmapto() — a consumer mapping gf -> <Plug>(...) before this file is
-- sourced must not suppress the target's definition.
if vim.fn.maparg('<Plug>(LogseqFollow)', 'n') == '' then
  vim.keymap.set('n', '<Plug>(LogseqFollow)', function()
    require('logseq').follow_link()
  end, { silent = true, desc = 'Logseq: follow link under cursor' })
end
-- No default key for cycling (repo convention, plus most terminals send
-- Ctrl+Enter as plain Enter). Suggested binds (README, M8):
-- GUI: vim.keymap.set('n', '<C-CR>', '<Plug>(LogseqCycleTodo)')
if vim.fn.maparg('<Plug>(LogseqCycleTodo)', 'n') == '' then
  vim.keymap.set('n', '<Plug>(LogseqCycleTodo)', function()
    require('logseq').cycle_todo()
  end, { silent = true, desc = 'Logseq: cycle TODO state on current line' })
end
-- Smart action + link navigation plugs (M9). The ftplugin maps graph
-- buffers to these; users can also bind them anywhere themselves, e.g.
-- vim.keymap.set('n', '<CR>', '<Plug>(LogseqSmartAction)', { buffer = true })
if vim.fn.maparg('<Plug>(LogseqSmartAction)', 'n') == '' then
  vim.keymap.set('n', '<Plug>(LogseqSmartAction)', function()
    require('logseq').smart_action()
  end, { silent = true, desc = 'Logseq: follow link, cycle task, or move down' })
end
if vim.fn.maparg('<Plug>(LogseqNextLink)', 'n') == '' then
  vim.keymap.set('n', '<Plug>(LogseqNextLink)', function()
    require('logseq').nav_link('next')
  end, { silent = true, desc = 'Logseq: jump to next link' })
end
if vim.fn.maparg('<Plug>(LogseqPrevLink)', 'n') == '' then
  vim.keymap.set('n', '<Plug>(LogseqPrevLink)', function()
    require('logseq').nav_link('prev')
  end, { silent = true, desc = 'Logseq: jump to previous link' })
end
