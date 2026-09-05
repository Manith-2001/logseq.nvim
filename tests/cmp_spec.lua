-- Source spec for lua/logseq/cmp.lua (M10.3): thin nvim-cmp wrapper.
-- No frameworks in CI — the module must load and complete with cmp
-- absent (kind falls back to LSP Text = 1 either way).
local cmp_src = require('logseq.cmp')

describe('logseq.cmp source (M10.3)', function()
  local prev_buf
  local scratch = {}
  local tmps = {}
  before_each(function()
    prev_buf = vim.api.nvim_get_current_buf()
  end)
  after_each(function()
    pcall(vim.api.nvim_set_current_buf, prev_buf)
    for _, b in ipairs(scratch) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    scratch = {}
    for _, t in ipairs(tmps) do
      vim.fn.delete(t, 'rf')
    end
    tmps = {}
  end)

  local function edit_graph_file(title)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    vim.fn.writefile({ '- lone' }, root .. '/pages/' .. title .. '.md')
    table.insert(tmps, root)
    vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/pages/' .. title .. '.md'))
    table.insert(scratch, vim.api.nvim_get_current_buf())
    return root
  end

  it('exposes [ and # triggers with per-buffer availability', function()
    local src = cmp_src.new()
    assert.are.same({ '[', '#' }, src:get_trigger_characters())
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(scratch, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'markdown'
    assert.is_false(src:is_available()) -- outside graphs: no b:logseq_root
    vim.b[buf].logseq_root = '/tmp/graph'
    assert.is_true(src:is_available())
    vim.bo[buf].filetype = 'text'
    assert.is_false(src:is_available())
  end)

  it('completes the cursor prefix through the core (no cmp needed)', function()
    edit_graph_file('mlflow')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[[ml ' })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    local got = nil
    cmp_src.new():complete({}, function(items)
      got = items
    end)
    assert.are.same({ { label = 'mlflow', kind = 1, detail = '● page' } }, got)
  end)

  it('calls back with {} outside a completion context', function()
    edit_graph_file('mlflow')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '- plain' })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    local got = nil
    cmp_src.new():complete({}, function(items)
      got = items
    end)
    assert.are.same({}, got)
  end)
end)
