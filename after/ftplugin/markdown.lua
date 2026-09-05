-- after/ftplugin/markdown.lua — graph-scoped buffer opts (M3).
-- Fires for every markdown buffer; applies only when the file lives
-- inside a Logseq graph. Detection is buffer-anchored (walk up from the
-- file itself), deliberately NOT config.graph_path: a global override must
-- not mark unrelated markdown files as graph pages.
-- Buffer-local only; never touches global options or keys.
local buf = vim.api.nvim_get_current_buf()
local name = vim.api.nvim_buf_get_name(buf)
if name == '' then
  return
end
local ok, graph = pcall(require, 'logseq.graph')
if not ok then
  return
end
local root = graph.find_root_from(name)
if not root then
  return
end
vim.b[buf].logseq_root = root
-- Logseq nests blocks with hard tabs (see PLAN.md §8.4); keep them literal
-- instead of expanding to spaces on indent.
vim.opt_local.expandtab = false
-- Buffer-local Logseq keys (M9, the documented exception to the
-- no-default-keys rule; user-removable via :nunmap <buffer>). Each key
-- is guarded independently: an existing map (user or otherwise) is never
-- clobbered, so partial user config still gets the remaining keys.
local function bufmap(lhs, fn, desc)
  if vim.fn.maparg(lhs, 'n') == '' then
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, desc = desc })
  end
end
bufmap('<CR>', function()
  require('logseq').smart_action()
end, 'Logseq: follow link, cycle task, or move down')
bufmap('[o', function()
  require('logseq').nav_link('prev')
end, 'Logseq: jump to previous link')
bufmap(']o', function()
  require('logseq').nav_link('next')
end, 'Logseq: jump to next link')
