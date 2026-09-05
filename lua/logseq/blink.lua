--- blink.cmp source (M10.3): parity wrapper over the completion core.
--- Never auto-registered: users opt in with
---   sources = { providers = { logseq = { module = 'logseq.blink' } } }
--- (see README). Loads with blink absent: no blink API is referenced;
--- items use plain LSP shapes (label/kind/detail).
local complete_mod = require('logseq.complete')

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

--- Enabled in graph markdown buffers only (same gate as the ftplugin).
---@return boolean
function source:enabled()
  return vim.bo.filetype == 'markdown' and vim.b.logseq_root ~= nil
end

---@return string[]
function source:get_trigger_characters()
  return { '[', '#' }
end

--- Complete from the live cursor (ctx ignored: the core re-derives
--- line + col, exactly like omnifunc, so blink and manual agree).
---@param _ table blink context (unused)
---@param callback function blink callback (required)
function source:get_completions(_, callback)
  if type(callback) ~= 'function' then
    return
  end
  local items = {}
  for _, item in ipairs(complete_mod.complete_at_cursor()) do
    table.insert(items, {
      label = item.title,
      kind = 1, -- LSP CompletionItemKind.Text
      detail = complete_mod.menu(item),
    })
  end
  callback({ items = items })
end

return source
