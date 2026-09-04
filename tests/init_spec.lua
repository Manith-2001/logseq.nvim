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

-- Shared harness for the M3 facade fns: tmp graph via opts.root (hermetic,
-- no config needed), clean home buffer per test, notify capture.
local function m3_harness()
  local H = {}
  H.notes = {}
  H.bufs = {}
  H.tmps = {}
  H.saved_cwd = vim.fn.getcwd()
  H.orig_notify = vim.notify
  H.orig_input = vim.ui.input
  H.config = require('logseq.config')
  function H.setup()
    -- Hermetic: minimal_init.lua pre-seeds vim.g.logseq; clear per test.
    H.saved_g = vim.g.logseq
    vim.g.logseq = nil
    H.config._reset()
    vim.notify = function(msg, level)
      table.insert(H.notes, { msg = msg, level = level })
    end
    H.saved_cwd = vim.fn.getcwd()
  end
  function H.teardown()
    vim.notify = H.orig_notify
    vim.ui.input = H.orig_input
    for _, b in ipairs(H.bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    for _, t in ipairs(H.tmps) do
      vim.fn.delete(t, 'rf')
    end
    vim.fn.chdir(H.saved_cwd)
    vim.g.logseq = H.saved_g
    H.config._reset()
  end
  -- Fresh tmp graph root with pages/ + journals/ dirs.
  function H.tmpgraph()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    table.insert(H.tmps, root)
    return root
  end
  -- Clean unmodified home buffer; :edit-based opens need this.
  function H.home()
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(H.bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = false
    return buf
  end
  function H.track_current()
    table.insert(H.bufs, vim.api.nvim_get_current_buf())
  end
  function H.notified(level, fragment)
    for _, n in ipairs(H.notes) do
      if n.level == level and n.msg:find(fragment, 1, true) then
        return true
      end
    end
    return false
  end
  return H
end

describe('today (M3)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('opens journals/<date>.md lazily without creating the file', function()
    local root = H.tmpgraph()
    H.home()
    logseq.today({ root = root, date = '2026_08_27' })
    H.track_current()
    local buf = vim.api.nvim_get_current_buf()
    assert.are.equal(
      vim.fn.resolve(root) .. '/journals/2026_08_27.md',
      vim.api.nvim_buf_get_name(buf)
    )
    assert.are.equal(0, vim.fn.filereadable(vim.api.nvim_buf_get_name(buf)))
    assert.is_true(vim.b[buf].logseq_dangling)
  end)

  it('defaults to os.date(journal_format)', function()
    local root = H.tmpgraph()
    H.home()
    logseq.today({ root = root })
    H.track_current()
    local stem = os.date(require('logseq.config').get().journal_format)
    assert.are.equal(
      vim.fn.resolve(root) .. '/journals/' .. stem .. '.md',
      vim.api.nvim_buf_get_name(0)
    )
  end)

  it('honors a custom journal_format', function()
    local root = H.tmpgraph()
    H.home()
    require('logseq.config').setup({ journal_format = '%Y-%m-%d' })
    logseq.today({ root = root })
    H.track_current()
    local stem = os.date('%Y-%m-%d')
    assert.are.equal(
      vim.fn.resolve(root) .. '/journals/' .. stem .. '.md',
      vim.api.nvim_buf_get_name(0)
    )
    require('logseq.config')._reset()
  end)

  it('errors with no graph root', function()
    H.home()
    vim.fn.chdir('/tmp') -- outside any graph; unnamed buf so cwd applies
    local buf = vim.api.nvim_get_current_buf()
    logseq.today()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)
end)

describe('new_page (M3)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('opens pages/<title>.md lazily without creating the file', function()
    local root = H.tmpgraph()
    H.home()
    logseq.new_page('M3 Page', { root = root })
    H.track_current()
    local buf = vim.api.nvim_get_current_buf()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/M3 Page.md', vim.api.nvim_buf_get_name(buf))
    assert.are.equal(0, vim.fn.filereadable(vim.api.nvim_buf_get_name(buf)))
    assert.is_true(vim.b[buf].logseq_dangling)
  end)

  it('accepts :LogseqNew cmd_opts ({args=title})', function()
    local root = H.tmpgraph()
    H.home()
    logseq.new_page({ args = 'Cmd Title' }, { root = root })
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Cmd Title.md', vim.api.nvim_buf_get_name(0))
  end)

  it('prompts when no title; opens the answer', function()
    local root = H.tmpgraph()
    H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm('Prompted Page')
    end
    logseq.new_page({ root = root })
    H.track_current()
    assert.are.equal(
      vim.fn.resolve(root) .. '/pages/Prompted Page.md',
      vim.api.nvim_buf_get_name(0)
    )
  end)

  it('cancel (nil input) stays put with an INFO note', function()
    local root = H.tmpgraph()
    local buf = H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm(nil)
    end
    logseq.new_page({ root = root })
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.INFO, 'new page cancelled'))
  end)

  it('blank input cancels too', function()
    local root = H.tmpgraph()
    local buf = H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm('   ')
    end
    logseq.new_page({ root = root })
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
  end)

  it('blank explicit title prompts instead of erroring', function()
    local root = H.tmpgraph()
    H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm('After Blank')
    end
    logseq.new_page('   ', { root = root })
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/After Blank.md', vim.api.nvim_buf_get_name(0))
  end)

  it('errors with no graph root', function()
    H.home()
    vim.fn.chdir('/tmp')
    local buf = vim.api.nvim_get_current_buf()
    logseq.new_page('Nope', {})
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)
end)
