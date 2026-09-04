-- Wiring spec for after/ftplugin/markdown.lua (M3): the logic
-- (graph.find_root_from) is unit-tested in graph_spec; here we check the
-- ftplugin gates correctly and sets buffer-local state inside a graph.
local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('after/ftplugin/markdown.lua (M3)', function()
  local saved_g
  local config = require('logseq.config')
  local bufs
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    bufs = {}
  end)
  after_each(function()
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.g.logseq = saved_g
    config._reset()
  end)

  local function edit(path)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    table.insert(bufs, vim.api.nvim_get_current_buf())
  end

  it('marks graph buffers and keeps hard tabs', function()
    edit(fixture .. '/pages/A.md')
    vim.cmd('runtime after/ftplugin/markdown.lua')
    assert.are.equal(fixture, vim.b.logseq_root)
    assert.is_false(vim.opt_local.expandtab:get())
  end)

  it('leaves non-graph buffers alone', function()
    local path = vim.fn.tempname() .. '.md'
    vim.fn.writefile({ '# scratch' }, path)
    edit(path)
    vim.fn.delete(path)
    vim.cmd('runtime after/ftplugin/markdown.lua')
    assert.is_nil(vim.b.logseq_root)
  end)
end)
