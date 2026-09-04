local logseq = require('logseq')
local config = require('logseq.config')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('follow_link (M2)', function()
  local saved_g
  local saved_cwd
  local orig_notify
  local notes
  local bufs
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    config.setup({ graph_path = fixture })
    notes = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notes, { msg = msg, level = level })
    end
    bufs = {}
    saved_cwd = vim.fn.getcwd()
  end)
  after_each(function()
    vim.notify = orig_notify
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.chdir(saved_cwd)
    vim.g.logseq = saved_g
    config._reset()
  end)

  -- Scratch window buffer with cursor placed; 0-based col like get_cursor().
  -- Marked unmodified so follow's :edit (which never forces) can switch.
  local function scratch(lines, col)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
    vim.api.nvim_win_set_cursor(0, { 1, col })
    return buf
  end

  local function notified(level, fragment)
    for _, n in ipairs(notes) do
      if n.level == level and n.msg:find(fragment, 1, true) then
        return true
      end
    end
    return false
  end

  it('follows [[A]] to the existing page', function()
    scratch({ '- see [[A]]' }, 8)
    logseq.follow_link()
    table.insert(bufs, vim.api.nvim_get_current_buf())
    assert.are.equal(fixture .. '/pages/A.md', vim.api.nvim_buf_get_name(0))
  end)

  it('opens a dangling page without creating the file', function()
    scratch({ '- see [[No Such Page M2]]' }, 10)
    logseq.follow_link()
    table.insert(bufs, vim.api.nvim_get_current_buf())
    local name = vim.api.nvim_buf_get_name(0)
    assert.are.equal(fixture .. '/pages/No Such Page M2.md', name)
    assert.are.equal(0, vim.fn.filereadable(name))
  end)

  it('warns and stays put with no link under cursor', function()
    local buf = scratch({ '- plain line' }, 3)
    logseq.follow_link()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(notified(vim.log.levels.WARN, 'no link under cursor'))
  end)

  it('errors with no graph root', function()
    config._reset() -- drop the fixture graph_path; g: is already nil
    vim.fn.chdir('/tmp') -- outside any graph, like the M1 strict case
    local buf = scratch({ '- [[A]]' }, 4)
    logseq.follow_link()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(notified(vim.log.levels.ERROR, 'graph root not found'))
  end)
end)
