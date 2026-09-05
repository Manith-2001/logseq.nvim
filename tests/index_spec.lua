local index = require('logseq.index')
local config = require('logseq.config')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('index.normalize (M6.1)', function()
  it('trims whitespace and preserves case/spaces', function()
    assert.are.equal('Machine Learning', index.normalize('  Machine Learning  '))
    assert.are.equal('A', index.normalize('A'))
  end)

  it('returns nil for blank or non-string input', function()
    assert.is_nil(index.normalize(''))
    assert.is_nil(index.normalize('   '))
    assert.is_nil(index.normalize(nil))
    assert.is_nil(index.normalize(42))
  end)
end)

describe('index.build on the fixture graph (M6.1)', function()
  local saved_g
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
  end)
  after_each(function()
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('builds forward/back with a dangling node', function()
    -- pages/A.md links [[World]] (missing), pages/B.md links [[A]].
    local idx = index.build(fixture)
    assert.are.same({ 'World' }, idx.forward['A'])
    assert.are.same({ 'A' }, idx.forward['B'])
    assert.are.same({}, idx.forward['2026_08_27'])
    assert.are.same({ 'B' }, idx.back['A'])
    assert.are.same({ 'A' }, idx.back['World'])
    assert.are.same({}, idx.back['B'])
    assert.are.equal('dangling', idx.nodes['World'].kind)
    assert.is_nil(idx.nodes['World'].path)
    assert.is_false(idx.nodes['World'].exists)
    assert.are.equal('page', idx.nodes['A'].kind)
    assert.are.equal('journal', idx.nodes['2026_08_27'].kind)
    assert.are.same({ pages = 2, journals = 1, dangling = 1, edges = 2 }, idx.stats)
  end)
end)

describe('index.build edge cases (M6.1)', function()
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

  local function mkgraph(files)
    local tmp = vim.fn.tempname()
    table.insert(tmps, tmp)
    vim.fn.mkdir(tmp .. '/pages', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
    for name, lines in pairs(files) do
      vim.fn.writefile(lines, tmp .. '/pages/' .. name .. '.md')
    end
    return tmp
  end

  it('dedupes repeat links and sorts targets', function()
    local root = mkgraph({ A = { '- [[Z]] and [[M]] and [[Z]] and [[M]]' } })
    local idx = index.build(root)
    assert.are.same({ 'M', 'Z' }, idx.forward['A'])
    assert.are.equal(2, idx.stats.edges)
  end)

  it('keeps self-loops in forward but not in back', function()
    local root = mkgraph({ A = { '- [[A]] and [[B]]' } })
    local idx = index.build(root)
    assert.are.same({ 'A', 'B' }, idx.forward['A'])
    assert.are.same({}, idx.back['A'])
    assert.are.same({ 'A' }, idx.back['B'])
  end)

  it('indexes #[[hash-wikilink]] and #hashtag targets', function()
    local root = mkgraph({ A = { '- #[[a b]] plus #tag here' } })
    local idx = index.build(root)
    assert.are.same({ 'a b', 'tag' }, idx.forward['A'])
    assert.are.same({ 'A' }, idx.back['a b'])
    assert.are.same({ 'A' }, idx.back['tag'])
  end)

  it('skips namespace targets containing /', function()
    local root = mkgraph({ A = { '- [[a/b]] and #x/y plus [[B]]' } })
    local idx = index.build(root)
    assert.are.same({ 'B' }, idx.forward['A'])
    assert.is_nil(idx.nodes['a/b'])
    assert.is_nil(idx.nodes['x/y'])
  end)

  it('trims targets and preserves case', function()
    local root = mkgraph({ A = { '- [[  Machine Learning  ]]' } })
    local idx = index.build(root)
    assert.are.same({ 'Machine Learning' }, idx.forward['A'])
    assert.is_true(idx.nodes['Machine Learning'].exists == false)
  end)

  it('skips blank links and unreadable files scan as no links', function()
    local root = mkgraph({ A = { '- [[]] and # done' } })
    local idx = index.build(root)
    assert.are.same({}, idx.forward['A'])
    assert.are.equal(0, idx.stats.edges)
  end)

  it('indexes journal links and counts journal nodes', function()
    local tmp = vim.fn.tempname()
    table.insert(tmps, tmp)
    vim.fn.mkdir(tmp .. '/pages', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
    vim.fn.writefile({ '- lone page' }, tmp .. '/pages/A.md')
    vim.fn.writefile({ '- journal refs [[A]]' }, tmp .. '/journals/2026_08_27.md')
    local idx = index.build(tmp)
    assert.are.same({ 'A' }, idx.forward['2026_08_27'])
    assert.are.same({ '2026_08_27', 'A' }, index.titles(idx))
    assert.are.same({ pages = 1, journals = 1, dangling = 0, edges = 1 }, idx.stats)
  end)

  it('returns an empty index when dirs are missing', function()
    local idx = index.build('/tmp/no-such-logseq-graph-xyz')
    assert.are.same({}, index.titles(idx))
    assert.are.same({ pages = 0, journals = 0, dangling = 0, edges = 0 }, idx.stats)
  end)

  it('errors on a missing root', function()
    assert.has_error(function()
      index.build('')
    end)
    assert.has_error(function()
      index.build(nil)
    end)
  end)
end)

describe('index accessors (M6.1)', function()
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

  local function chain()
    local tmp = vim.fn.tempname()
    table.insert(tmps, tmp)
    vim.fn.mkdir(tmp .. '/pages', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
    vim.fn.writefile({ '- [[B]]' }, tmp .. '/pages/A.md')
    vim.fn.writefile({ '- [[C]]' }, tmp .. '/pages/B.md')
    vim.fn.writefile({ '- lone' }, tmp .. '/pages/C.md')
    return tmp
  end

  it('forward/back return copies and {} for unknown titles', function()
    local idx = index.build(chain())
    assert.are.same({ 'B' }, index.forward(idx, 'A'))
    assert.are.same({ 'A' }, index.back(idx, 'B'))
    assert.are.same({}, index.forward(idx, 'Nope'))
    assert.are.same({}, index.back(idx, 'Nope'))
    local fwd = index.forward(idx, 'A')
    table.insert(fwd, 'MUT')
    assert.are.same({ 'B' }, index.forward(idx, 'A'))
  end)

  it('neighbors walks both directions with depth', function()
    local idx = index.build(chain())
    assert.are.same({ 'B' }, index.neighbors(idx, 'A', 1))
    assert.are.same({ 'B', 'C' }, index.neighbors(idx, 'A', 2))
    assert.are.same({ 'A', 'C' }, index.neighbors(idx, 'B', 1))
    assert.are.same({}, index.neighbors(idx, 'Nope', 2))
    assert.are.same({}, index.neighbors(idx, 'A', 0))
  end)

  it('titles lists every node sorted', function()
    local idx = index.build(chain())
    assert.are.same({ 'A', 'B', 'C' }, index.titles(idx))
  end)
end)

describe('index.occurrences (M8.1)', function()
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

  local function mkgraph(files)
    local tmp = vim.fn.tempname()
    table.insert(tmps, tmp)
    vim.fn.mkdir(tmp .. '/pages', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
    for name, lines in pairs(files) do
      vim.fn.writefile(lines, tmp .. '/pages/' .. name .. '.md')
    end
    return tmp
  end

  it('records one row per occurrence on the fixture graph', function()
    local idx = index.build(fixture)
    assert.are.same({
      { src = 'A', dst = 'World', lnum = 1, line = '- Hello [[World]]' },
    }, index.occurrences(idx, 'World'))
    assert.are.same({
      { src = 'B', dst = 'A', lnum = 1, line = '- Ref to [[A]]' },
    }, index.occurrences(idx, 'A'))
    assert.are.same({}, index.occurrences(idx, 'B'))
    assert.are.same({}, index.occurrences(idx, 'Nope'))
  end)

  it('keeps multiple rows for repeat links without deduping', function()
    local root = mkgraph({ A = { '- [[B]] and [[B]]', '- second [[B]]' }, B = { '- lone' } })
    local idx = index.build(root)
    -- forward dedupes to one edge, but occurrences keep all three rows.
    assert.are.same({ 'B' }, idx.forward['A'])
    assert.are.equal(1, idx.stats.edges)
    assert.are.same({
      { src = 'A', dst = 'B', lnum = 1, line = '- [[B]] and [[B]]' },
      { src = 'A', dst = 'B', lnum = 1, line = '- [[B]] and [[B]]' },
      { src = 'A', dst = 'B', lnum = 2, line = '- second [[B]]' },
    }, index.occurrences(idx, 'B'))
  end)

  it('sorts by (src, lnum)', function()
    local root = mkgraph({
      A = { '- lone', '- late [[T]]' },
      B = { '- early [[T]]', '- later [[T]]' },
    })
    local idx = index.build(root)
    local got = index.occurrences(idx, 'T')
    local keys = {}
    for _, occ in ipairs(got) do
      table.insert(keys, occ.src .. ':' .. occ.lnum)
    end
    assert.are.same({ 'A:2', 'B:1', 'B:2' }, keys)
  end)

  it('skips namespace and blank targets like forward[]', function()
    local root = mkgraph({ A = { '- [[a/b]] and [[]] plus [[B]]' } })
    local idx = index.build(root)
    assert.are.same({ 'B' }, idx.forward['A'])
    assert.are.same({
      { src = 'A', dst = 'B', lnum = 1, line = '- [[a/b]] and [[]] plus [[B]]' },
    }, index.occurrences(idx, 'B'))
    assert.are.same({}, index.occurrences(idx, 'a/b'))
    assert.is_nil(idx.nodes['a/b'])
  end)

  it('keeps self-loops in the stored list but excludes them from back-context', function()
    local root = mkgraph({ A = { '- [[A]] and [[B]]' } })
    local idx = index.build(root)
    assert.are.same({ 'A', 'B' }, idx.forward['A'])
    assert.are.same({}, idx.back['A'])
    -- Stored list keeps the self-loop for forward-context; accessor mirrors back[].
    assert.are.equal(2, #idx.occurrences)
    assert.are.same({}, index.occurrences(idx, 'A'))
    assert.are.same({
      { src = 'A', dst = 'B', lnum = 1, line = '- [[A]] and [[B]]' },
    }, index.occurrences(idx, 'B'))
  end)

  it('returns {} for unknown/non-string dst and copies rows', function()
    local root = mkgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    local idx = index.build(root)
    assert.are.same({}, index.occurrences(idx, 'Nope'))
    assert.are.same({}, index.occurrences(idx, nil))
    assert.are.same({}, index.occurrences(idx, 42))
    local first = index.occurrences(idx, 'B')
    first[1].src = 'MUT'
    table.insert(first, { src = 'X', dst = 'B', lnum = 9, line = 'x' })
    local again = index.occurrences(idx, 'B')
    assert.are.same({
      { src = 'A', dst = 'B', lnum = 1, line = '- [[B]]' },
    }, again)
  end)
end)
