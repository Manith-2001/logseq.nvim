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
