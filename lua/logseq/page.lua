--- Page title <-> path mapping (M1) + lazy open (M2).
--- Escaping (finalized M4 per §8.1 finding): titles map VERBATIM
--- (spaces/case preserved). The reference graph has no active
--- `:file-name-format` (only a commented `:journal/file-name-format`),
--- zero `___` files, zero subdirs, and zero `[[a/b]]` links — so there is
--- no in-graph evidence for `___`/legacy translation, and inventing one
--- would diverge from Logseq on this graph. `/` therefore passes through
--- at this layer (`[[a/b]]` -> `pages/a/b.md`); the UX layer
--- (`follow_link`, `new_page`) refuses such titles with a warning since
--- namespace pages are out of scope for v0.1 (see §2 non-goals).
local config = require('logseq.config')

local M = {}

--- Canonical path for a page title under root's pages dir.
--- Logseq trims surrounding whitespace in page names, so we do too.
---@param root string absolute graph root
---@param title string page title, e.g. 'Machine Learning'
---@return string absolute path, e.g. '<root>/pages/Machine Learning.md'
function M.title_to_path(root, title)
  assert(type(root) == 'string' and root ~= '', 'page.title_to_path: root required')
  assert(type(title) == 'string', 'page.title_to_path: title required')
  local name = title:match('^%s*(.-)%s*$')
  assert(name ~= '', 'page.title_to_path: title must not be blank')
  return root .. '/' .. config.get().pages_dir .. '/' .. name .. '.md'
end

---@param path string
---@return boolean
function M.exists(path)
  return vim.fn.filereadable(path) == 1
end

--- Canonical path for a journal stem under root's journals dir.
--- The stem is normally os.date(config.journal_format), e.g. '2026_08_27'.
---@param root string absolute graph root
---@param stem string filename without .md, e.g. '2026_08_27'
---@return string absolute path, e.g. '<root>/journals/2026_08_27.md'
function M.journal_to_path(root, stem)
  assert(type(root) == 'string' and root ~= '', 'page.journal_to_path: root required')
  assert(type(stem) == 'string', 'page.journal_to_path: stem required')
  local name = stem:match('^%s*(.-)%s*$')
  assert(name ~= '', 'page.journal_to_path: stem must not be blank')
  return root .. '/' .. config.get().journals_dir .. '/' .. name .. '.md'
end

--- True when every line of buf is blank (a dangling page with no content).
---@param buf integer
---@return boolean
local function buf_is_blank(buf)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if not line:match('^%s*$') then
      return false
    end
  end
  return true
end

--- Refuse `:w` on a dangling (never-existed) buffer that is still empty:
--- Logseq deletes empty pages, so writing a 0-byte file would immediately
--- diverge from the graph. Warn + abort the write; once the buffer has
--- content (or the file exists) writes proceed normally.
--- Single `augroup LogseqNvim`, created once (M4 idempotency): repeated
--- open_lazy() calls must not churn or duplicate autocmds.
local write_guard_ready = false
local function ensure_write_guard()
  if write_guard_ready then
    return
  end
  write_guard_ready = true
  local group = vim.api.nvim_create_augroup('LogseqNvim', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePre', {
    group = group,
    callback = function(args)
      if vim.b[args.buf].logseq_dangling and not M.exists(args.file) and buf_is_blank(args.buf) then
        vim.notify('logseq.nvim: not writing empty page (add content first)', vim.log.levels.WARN)
        error('logseq.nvim: refusing to write empty page', 0)
      end
    end,
    desc = 'Logseq: refuse :w on empty dangling page',
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(args)
      if M.exists(args.file) then
        vim.b[args.buf].logseq_dangling = nil
      end
    end,
    desc = 'Logseq: clear dangling flag once the page file exists',
  })
end

--- Open path for editing without creating anything on disk (dangling-ref
--- semantics): a missing page opens as an empty buffer; the file appears
--- only after content is added and `:w` succeeds. Never writes.
---@param path string absolute page path
---@return integer bufnr of the opened buffer
function M.open_lazy(path)
  assert(type(path) == 'string' and path ~= '', 'page.open_lazy: path required')
  ensure_write_guard()
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  vim.bo.filetype = 'markdown'
  local buf = vim.api.nvim_get_current_buf()
  if not M.exists(path) then
    vim.b[buf].logseq_dangling = true
  end
  return buf
end

return M
