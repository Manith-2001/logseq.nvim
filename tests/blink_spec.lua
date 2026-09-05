-- Source spec for lua/logseq/blink.lua (M10.3): blink.cmp parity wrapper.
-- Mirrors tests/cmp_spec.lua: triggers, per-buffer gate, core-backed
-- completions, all with blink absent.
local blink_src = require('logseq.blink')

describe('logseq.blink source (M10.3)', function()
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

  it('exposes [ and # triggers with per-buffer gate', function()
    local src = blink_src.new()
    assert.are.same({ '[', '#' }, src:get_trigger_characters())
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(scratch, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'markdown'
    assert.is_false(src:enabled()) -- outside graphs: no b:logseq_root
    vim.b[buf].logseq_root = '/tmp/graph'
    assert.is_true(src:enabled())
    vim.bo[buf].filetype = 'text'
    assert.is_false(src:enabled())
  end)

  it('completes the cursor prefix through the core (no blink needed)', function()
    edit_graph_file('mlflow')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[[ml' })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    local got = nil
    blink_src.new():get_completions({}, function(response)
      got = response
    end)
    assert.are.same({ items = { { label = 'mlflow', kind = 1, detail = '● page' } } }, got)
  end)

  it('responds with no items outside a completion context', function()
    edit_graph_file('mlflow')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '- plain' })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    local got = nil
    blink_src.new():get_completions({}, function(response)
      got = response
    end)
    assert.are.same({ items = {} }, got)
  end)
end)
