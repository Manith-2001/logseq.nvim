local page = require('logseq.page')
local config = require('logseq.config')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('page.title_to_path (M1)', function()
  local saved_g
  before_each(function()
    -- Hermetic: minimal_init.lua pre-seeds vim.g.logseq; clear per test.
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
  end)
  after_each(function()
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('preserves spaces and case (§8.1: verbatim mapping)', function()
    assert.are.equal(
      fixture .. '/pages/Machine Learning.md',
      page.title_to_path(fixture, 'Machine Learning')
    )
  end)

  it('trims surrounding whitespace like Logseq does', function()
    assert.are.equal(fixture .. '/pages/A.md', page.title_to_path(fixture, '  A  '))
  end)

  it('passes / through verbatim at the mapping layer (M4: guard lives in the facade)', function()
    assert.are.equal(fixture .. '/pages/a/b.md', page.title_to_path(fixture, 'a/b'))
  end)

  it('errors on missing or blank titles', function()
    assert.has_error(function()
      page.title_to_path(fixture, '')
    end)
    assert.has_error(function()
      page.title_to_path(fixture, '   ')
    end)
  end)
end)

describe('page.exists (M1)', function()
  it('is true for a real page and false for a missing one', function()
    assert.is_true(page.exists(fixture .. '/pages/A.md'))
    assert.is_false(page.exists(fixture .. '/pages/No Such Page.md'))
  end)
end)

describe('page.open_lazy (M2)', function()
  local saved_g
  local tmpdir
  local bufs
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    bufs = {}
    tmpdir = vim.fn.tempname() .. '_logseq'
    vim.fn.mkdir(tmpdir, 'p')
  end)
  after_each(function()
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.delete(tmpdir, 'rf')
    vim.g.logseq = saved_g
    config._reset()
  end)

  local function write_file(path, content)
    local f = assert(io.open(path, 'w'))
    f:write(content)
    f:close()
  end

  it('opens an existing page with content and markdown filetype', function()
    local path = tmpdir .. '/A.md'
    write_file(path, '- hello\n')
    local buf = page.open_lazy(path)
    table.insert(bufs, buf)
    -- :edit resolves symlinks (macOS /var -> /private/var); compare canonical.
    assert.are.equal(vim.fn.resolve(path), vim.api.nvim_buf_get_name(buf))
    assert.are.same({ '- hello' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.are.equal('markdown', vim.api.nvim_get_option_value('filetype', { buf = buf }))
    assert.is_nil(vim.b[buf].logseq_dangling)
  end)

  it('opens a missing page without creating the file (dangling)', function()
    local path = tmpdir .. '/Missing.md'
    local buf = page.open_lazy(path)
    table.insert(bufs, buf)
    assert.are.equal(vim.fn.resolve(path), vim.api.nvim_buf_get_name(buf))
    assert.are.equal(0, vim.fn.filereadable(path))
    assert.is_true(vim.b[buf].logseq_dangling)
  end)

  it(':w on an empty dangling buffer warns and refuses', function()
    local path = tmpdir .. '/Empty.md'
    local buf = page.open_lazy(path)
    table.insert(bufs, buf)
    local notes = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notes, { msg = msg, level = level })
    end
    local ok = pcall(vim.cmd, 'write')
    vim.notify = orig_notify
    assert.is_false(ok)
    assert.are.equal(0, vim.fn.filereadable(path))
    local warned = false
    for _, n in ipairs(notes) do
      if n.level == vim.log.levels.WARN and n.msg:find('empty page') then
        warned = true
      end
    end
    assert.is_true(warned)
  end)

  it(':w succeeds once the page has content, then the file exists', function()
    local path = tmpdir .. '/Filled.md'
    local buf = page.open_lazy(path)
    table.insert(bufs, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- now with content' })
    vim.cmd('write')
    assert.are.equal(1, vim.fn.filereadable(path))
    assert.is_nil(vim.b[buf].logseq_dangling)
  end)
end)
