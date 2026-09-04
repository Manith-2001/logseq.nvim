local graph = require('logseq.graph')
local config = require('logseq.config')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('graph.find_root (M1)', function()
  local saved_g
  before_each(function()
    -- Hermetic: minimal_init.lua pre-seeds vim.g.logseq, and get() now
    -- honors g: without setup(), so clear it per test (restore after).
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
  end)
  after_each(function()
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('finds the root upward from a nested page file', function()
    assert.are.equal(fixture, graph.find_root(fixture .. '/pages/A.md'))
  end)

  it('finds the root from the root itself and from a journal file', function()
    assert.are.equal(fixture, graph.find_root(fixture))
    assert.are.equal(fixture, graph.find_root(fixture .. '/journals/2026_08_27.md'))
  end)

  it('returns nil outside any graph', function()
    assert.is_nil(graph.find_root('/tmp/no-such-logseq-graph-xyz'))
  end)

  it('prefers explicit config.graph_path over auto-detect', function()
    config.setup({ graph_path = fixture })
    assert.are.equal(fixture, graph.find_root('/tmp'))
  end)

  it('is strict: configured-but-missing graph_path returns nil', function()
    config.setup({ graph_path = fixture .. '/does-not-exist' })
    assert.is_nil(graph.find_root(fixture .. '/pages/A.md'))
  end)

  it('expands ~ in graph_path', function()
    config.setup({ graph_path = '~/' })
    assert.are.equal(vim.fn.expand('~/'):gsub('/+$', ''), graph.find_root())
  end)
end)

describe('graph.list_pages (M1)', function()
  local saved_g
  before_each(function()
    -- Hermetic: minimal_init.lua pre-seeds vim.g.logseq, and get() now
    -- honors g: without setup(), so clear it per test (restore after).
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
  end)
  after_each(function()
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('lists fixture pages + journals with kinds and paths', function()
    local items = graph.list_pages(fixture)
    local by_title = {}
    for _, item in ipairs(items) do
      by_title[item.title] = item
    end
    assert.are.equal('page', by_title['A'].kind)
    assert.are.equal(fixture .. '/pages/A.md', by_title['A'].path)
    assert.are.equal('page', by_title['B'].kind)
    assert.are.equal('journal', by_title['2026_08_27'].kind)
    assert.are.equal(fixture .. '/journals/2026_08_27.md', by_title['2026_08_27'].path)
    assert.are.equal(3, #items)
  end)

  it('excludes hidden files, non-md files, and subdirs (non-recursive)', function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. '/pages/sub', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
    vim.fn.writefile({ '- x' }, tmp .. '/pages/Visible.md')
    vim.fn.writefile({ '- hidden' }, tmp .. '/pages/.hidden.md')
    vim.fn.writefile({ '- nested' }, tmp .. '/pages/sub/Nested.md')
    vim.fn.writefile({ 'not markdown' }, tmp .. '/pages/notes.txt')
    local items = graph.list_pages(tmp)
    assert.are.equal(1, #items)
    assert.are.equal('Visible', items[1].title)
    assert.are.equal('page', items[1].kind)
    vim.fn.delete(tmp, 'rf')
  end)

  it('returns {} when the dirs are missing', function()
    assert.are.same({}, graph.list_pages('/tmp/no-such-logseq-graph-xyz'))
  end)
end)

describe('graph.find_root_from (M3)', function()
  local saved_g
  local tmps
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    tmps = {}
  end)
  after_each(function()
    for _, t in ipairs(tmps) do
      vim.fn.delete(t, 'rf')
    end
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('locates the root from a nested file, ignoring config.graph_path', function()
    config.setup({ graph_path = '/tmp' }) -- override points elsewhere...
    -- ...yet the buffer-anchored search still finds the real graph.
    assert.are.equal(fixture, graph.find_root_from(fixture .. '/pages/A.md'))
  end)

  it('returns nil outside any graph even with graph_path set', function()
    config.setup({ graph_path = fixture })
    assert.is_nil(graph.find_root_from('/tmp/no-such-logseq-graph-xyz/f.md'))
  end)

  it('detects a root via logseq/config.edn alone', function()
    local tmp = vim.fn.tempname()
    table.insert(tmps, tmp)
    vim.fn.mkdir(tmp .. '/logseq', 'p')
    vim.fn.writefile({ '{:x 1}' }, tmp .. '/logseq/config.edn')
    -- walk_up does not resolve symlinks, so expect tmp verbatim.
    assert.are.equal(tmp, graph.find_root_from(tmp .. '/logseq/config.edn'))
  end)

  it('is nil-safe', function()
    assert.is_nil(graph.find_root_from(nil))
    assert.is_nil(graph.find_root_from(''))
  end)
end)
