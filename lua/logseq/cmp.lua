--- nvim-cmp source (M10.3): thin wrapper over the completion core.
--- Never auto-registered: users opt in with
---   require('cmp').register_source('logseq', require('logseq.cmp').new())
--- (see README). Loads and runs with cmp absent (CI has no frameworks):
--- the only cmp touchpoint is the item-kind lookup, guarded by pcall
--- with an LSP fallback (CompletionItemKind.Text == 1).
local complete_mod = require('logseq.complete')

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

--- Available in graph markdown buffers only (same gate as the ftplugin).
---@return boolean
function source:is_available()
  return vim.bo.filetype == 'markdown' and vim.b.logseq_root ~= nil
end

---@return string[]
function source:get_trigger_characters()
  return { '[', '#' }
end

--- LSP Text kind without requiring cmp.
---@return integer
local function text_kind()
  local ok, cmp = pcall(require, 'cmp')
  if ok and cmp ~= nil and cmp.lsp ~= nil and cmp.lsp.CompletionItemKind ~= nil then
    return cmp.lsp.CompletionItemKind.Text or 1
  end
  return 1
end

--- Complete from the live cursor (params ignored: the core re-derives
--- line + col, exactly like omnifunc, so cmp and manual agree).
---@param _ table cmp params (unused)
---@param callback function cmp callback (required)
function source:complete(_, callback)
  if type(callback) ~= 'function' then
    return
  end
  local items = {}
  for _, item in ipairs(complete_mod.complete_at_cursor()) do
    table.insert(items, {
      label = item.title,
      kind = text_kind(),
      detail = complete_mod.menu(item),
    })
  end
  callback(items)
end

return source
