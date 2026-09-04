--- Page title <-> path mapping (M1). Lazy open lands in M2 (open_lazy).
--- Escaping: spaces/case preserved verbatim per §8.1 discovery (no
--- `:file-name-format` set, no namespace files in the reference graph).
--- `/` handling deferred to M4.
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

return M
