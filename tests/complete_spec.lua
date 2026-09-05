local complete = require('logseq.complete')

-- M10.0 contract: open-context detection. Cols are 1-based cursor cols
-- (where the next char would insert); startcol is the 1-based col where
-- the prefix starts (omnifunc findstart convention). Red by design
-- against the M10.0 stubs; M10.1 turns them green.
describe('complete.find_start (M10.0 contract)', function()
  it('detects an empty [[ with an empty prefix', function()
    assert.are.same({ startcol = 3, prefix = '', kind = 'wikilink' }, complete.find_start('[[', 3))
  end)

  it('detects [[ml with prefix ml', function()
    assert.are.same(
      { startcol = 3, prefix = 'ml', kind = 'wikilink' },
      complete.find_start('[[ml', 5)
    )
  end)

  it('detects #[[ml as a hash-wikilink', function()
    assert.are.same(
      { startcol = 6, prefix = 'ml', kind = 'hash-wikilink' },
      complete.find_start('- #[[ml', 8)
    )
  end)

  it('detects #ml as a hashtag', function()
    assert.are.same(
      { startcol = 6, prefix = 'ml', kind = 'hashtag' },
      complete.find_start('see #ml', 8)
    )
  end)

  it('returns nil after a closed ]]', function()
    assert.is_nil(complete.find_start('[[A]] ', 7))
  end)

  it('picks the last open [[ when several share a line', function()
    assert.are.same(
      { startcol = 9, prefix = 'm', kind = 'wikilink' },
      complete.find_start('[[A]] [[m', 10)
    )
  end)

  it('works on tab-indented Logseq blocks', function()
    assert.are.same(
      { startcol = 6, prefix = 'ml', kind = 'wikilink' },
      complete.find_start('\t- [[ml', 8)
    )
  end)

  it('is nil-safe and quiet on plain text', function()
    assert.is_nil(complete.find_start(nil, 1))
    assert.is_nil(complete.find_start('[[', nil))
    assert.is_nil(complete.find_start('- plain', 3))
  end)
end)

describe('complete.rank/complete (M10.0 contract)', function()
  it('ranks prefix before fuzzy and drops non-matches', function()
    assert.are.same({ 'mlflow', 'Amble' }, complete.rank('ml', { 'Zebra', 'mlflow', 'Amble' }))
  end)

  it('complete returns shaped items for injected titles', function()
    local items = complete.complete('ml', {
      items = { { title = 'mlflow', kind = 'page', path = '/x', exists = true } },
    })
    assert.are.equal(1, #items)
    assert.are.equal('mlflow', items[1].title)
    assert.is_true(items[1].exists)
  end)
end)

describe('complete.rank tiers (M10.1)', function()
  it('offers everything alphabetically on an empty prefix', function()
    assert.are.same({ 'A', 'B' }, complete.rank('', { 'B', 'A' }))
  end)

  it('orders prefix before substring before fuzzy, case-insensitively', function()
    assert.are.same(
      { 'ML', 'mlflow', 'Amble' },
      complete.rank('ml', { 'Amble', 'mlflow', 'Zebra', 'ML' })
    )
    assert.are.same(
      { 'amp', 'Camp', 'Example' },
      complete.rank('amp', { 'Example', 'amp', 'Camp' })
    )
  end)

  it('never mutates the input and tolerates bad input', function()
    local titles = { 'B', 'A' }
    complete.rank('', titles)
    assert.are.same({ 'B', 'A' }, titles)
    assert.are.same({ 'A', 'B' }, complete.rank(nil, { 'B', 'A' }))
    assert.are.same({}, complete.rank('x', nil))
  end)
end)

describe('complete against a graph (M10.1)', function()
  local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
  local fixture = repo .. '/tests/fixtures/graph'
  -- Fixture: pages A (-> [[World]]), B (-> [[A]]), journal 2026_08_27.

  local function titles(items)
    local out = {}
    for i, item in ipairs(items) do
      out[i] = item.title
    end
    return out
  end

  it('lists existing before dangling on an empty prefix', function()
    local items = complete.complete('', { root = fixture })
    assert.are.same({ '2026_08_27', 'A', 'B', 'World' }, titles(items))
    assert.is_true(items[1].exists)
    assert.are.equal('journal', items[1].kind)
    assert.are.equal('World', items[4].title)
    assert.are.equal('dangling', items[4].kind)
    assert.is_nil(items[4].path)
    assert.is_false(items[4].exists)
  end)

  it('filters to a dangling title with full item shape', function()
    assert.are.same(
      { { title = 'World', kind = 'dangling', path = nil, exists = false } },
      complete.complete('wor', { root = fixture })
    )
  end)

  it('returns {} with no match, no root, or a missing dir', function()
    assert.are.same({}, complete.complete('zzz', { root = fixture }))
    assert.are.same({}, complete.complete('', { root = fixture .. '-missing' }))
  end)

  it('truncates after ranking when opts.limit is set', function()
    local items = complete.complete('', { root = fixture, limit = 2 })
    assert.are.same({ '2026_08_27', 'A' }, titles(items))
  end)

  it('returns {} when no graph root resolves', function()
    local config = require('logseq.config')
    local graph = require('logseq.graph')
    local saved_g, saved_cwd = vim.g.logseq, vim.fn.getcwd()
    vim.g.logseq = nil
    config._reset()
    graph._set_state_file(vim.fn.tempname())
    vim.fn.chdir('/tmp')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    local ok, items = pcall(complete.complete, 'x')
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.chdir(saved_cwd)
    vim.g.logseq = saved_g
    config._reset()
    graph._set_state_file(nil)
    assert.is_true(ok)
    assert.are.same({}, items)
  end)
end)

describe('complete.omnifunc (M10.1)', function()
  local prev_buf = nil
  local scratch = {}
  local tmps = {}

  local function use_buf(lines)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(scratch, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

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

  it('returns -1 / {} outside a completion context', function()
    use_buf({ '- plain' })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    assert.are.equal(-1, complete.omnifunc(1, ''))
    assert.are.same({}, complete.omnifunc(0, ''))
  end)

  it('returns the 0-based prefix col on findstart', function()
    use_buf({ '[[ml' })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    assert.are.equal(2, complete.omnifunc(1, ''))
  end)

  it('returns word/menu dicts for the buffer prefix', function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p') -- both dirs: is_root needs the pair
    vim.fn.writefile({ '- lone' }, root .. '/pages/mlflow.md')
    table.insert(tmps, root)
    vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/pages/mlflow.md'))
    table.insert(scratch, vim.api.nvim_get_current_buf())
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[[ml' })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    assert.are.same({ { word = 'mlflow', menu = '● page' } }, complete.omnifunc(0, 'ml'))
  end)
end)
