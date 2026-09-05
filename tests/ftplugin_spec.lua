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

  it('sets buffer-local smart action and link keys in graph buffers', function()
    edit(fixture .. '/pages/A.md')
    vim.cmd('runtime after/ftplugin/markdown.lua')
    for _, lhs in ipairs({ '<CR>', '[o', ']o' }) do
      local map = vim.fn.maparg(lhs, 'n', false, true)
      assert.are.equal(1, map.buffer)
      assert.is_not_nil(map.callback)
    end
  end)

  it('<CR> key follows the link under the cursor', function()
    edit(fixture .. '/pages/A.md') -- single line: - Hello [[World]]
    vim.cmd('runtime after/ftplugin/markdown.lua')
    vim.api.nvim_win_set_cursor(0, { 1, 8 }) -- on the '[[' of [[World]]
    vim.fn.maparg('<CR>', 'n', false, true).callback()
    table.insert(bufs, vim.api.nvim_get_current_buf())
    assert.are.equal(fixture .. '/pages/World.md', vim.api.nvim_buf_get_name(0))
  end)

  it(']o / [o keys move between links without wrapping', function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. '/pages', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
    local path = tmp .. '/pages/Links.md'
    vim.fn.writefile({ 'see [[One]] and [[Two]]' }, path)
    edit(path)
    vim.cmd('runtime after/ftplugin/markdown.lua')
    vim.fn.delete(tmp, 'rf') -- detection done; the open buffer suffices
    local next_link = vim.fn.maparg(']o', 'n', false, true).callback
    local prev_link = vim.fn.maparg('[o', 'n', false, true).callback
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    next_link()
    assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(0)) -- [[One]]
    next_link()
    assert.are.same({ 1, 16 }, vim.api.nvim_win_get_cursor(0)) -- [[Two]]
    next_link() -- no wrap
    assert.are.same({ 1, 16 }, vim.api.nvim_win_get_cursor(0))
    prev_link()
    assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(0))
  end)

  it('never clobbers user maps', function()
    edit(fixture .. '/pages/A.md')
    -- Clear whatever the FileType autocmd may have set so the guard is
    -- what keeps the user map below (not map-application order).
    vim.cmd('silent! nunmap <buffer> <CR>')
    vim.keymap.set('n', '<CR>', 'j', { buffer = true, silent = true })
    vim.cmd('runtime after/ftplugin/markdown.lua')
    assert.are.equal('j', vim.fn.maparg('<CR>', 'n', false, true).rhs)
    -- Sibling keys are guarded independently and still get wired.
    assert.are.equal(1, vim.fn.maparg(']o', 'n', false, true).buffer)
  end)

  it('non-graph buffers get no Logseq keys', function()
    local path = vim.fn.tempname() .. '.md'
    vim.fn.writefile({ '# scratch' }, path)
    edit(path)
    vim.fn.delete(path)
    vim.cmd('runtime after/ftplugin/markdown.lua')
    for _, lhs in ipairs({ '<CR>', '[o', ']o' }) do
      assert.are.same({}, vim.fn.maparg(lhs, 'n', false, true))
    end
  end)
end)
