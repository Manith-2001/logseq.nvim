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
    -- Trailing space: normal-mode set_cursor clamps past-EOL, but
    -- insert-mode EOL sits one past the last char; this reproduces the
    -- exact insert-mode (line, col) without changing the context.
    use_buf({ '[[ml ' })
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
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[[ml ' })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    assert.are.same({ { word = 'mlflow', menu = '● page' } }, complete.omnifunc(0, 'ml'))
  end)
end)

describe('complete dangling cache (M10.2)', function()
  local tmps = {}
  after_each(function()
    for _, t in ipairs(tmps) do
      vim.fn.delete(t, 'rf')
    end
    tmps = {}
  end)

  local function mkroot(link_line)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    vim.fn.writefile({ link_line }, root .. '/pages/Soda.md')
    table.insert(tmps, root)
    return root
  end

  local function titles(items)
    local out = {}
    for i, item in ipairs(items) do
      out[i] = item.title
    end
    return out
  end

  it('serves dangling titles stale until invalidate() drops the cache', function()
    local root = mkroot('- [[Fizz]]')
    assert.are.same({ 'Soda', 'Fizz' }, titles(complete.complete('', { root = root })))
    vim.fn.writefile({ '- no links here' }, root .. '/pages/Soda.md')
    -- Stale by design: the cached index still advertises Fizz.
    assert.are.same({ 'Soda', 'Fizz' }, titles(complete.complete('', { root = root })))
    complete.invalidate(root)
    assert.are.same({ 'Soda' }, titles(complete.complete('', { root = root })))
  end)

  it('invalidate() with no root clears every cached root', function()
    local a, b = mkroot('- [[Fizz]]'), mkroot('- [[Buzz]]')
    assert.are.same({ 'Soda', 'Fizz' }, titles(complete.complete('', { root = a })))
    assert.are.same({ 'Soda', 'Buzz' }, titles(complete.complete('', { root = b })))
    vim.fn.writefile({ '- no links here' }, a .. '/pages/Soda.md')
    vim.fn.writefile({ '- no links here' }, b .. '/pages/Soda.md')
    complete.invalidate()
    assert.are.same({ 'Soda' }, titles(complete.complete('', { root = a })))
    assert.are.same({ 'Soda' }, titles(complete.complete('', { root = b })))
  end)
end)

describe('complete graph_max_files fallback (M10.2)', function()
  local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
  local fixture = repo .. '/tests/fixtures/graph'
  local config = require('logseq.config')
  local saved_g, saved_notify
  local notes = {}
  before_each(function()
    saved_g = vim.g.logseq
    saved_notify = vim.notify
    notes = {}
    vim.notify = function(msg, level)
      table.insert(notes, { msg = msg, level = level })
    end
  end)
  after_each(function()
    vim.notify = saved_notify
    vim.g.logseq = saved_g
    config._reset()
    require('logseq.complete').invalidate()
  end)

  local function warned(fragment)
    for _, n in ipairs(notes) do
      if n.level == vim.log.levels.WARN and n.msg:find(fragment, 1, true) then
        return true
      end
    end
    return false
  end

  it('offers pages only plus one WARN over graph_max_files', function()
    config.setup({ graph_max_files = 1 }) -- fixture holds 3 files
    local items = complete.complete('', { root = fixture })
    local got = {}
    for i, item in ipairs(items) do
      got[i] = item.title
    end
    assert.are.same({ '2026_08_27', 'A', 'B' }, got) -- no dangling World
    assert.is_true(warned('too large'))
    local n = #notes
    complete.complete('', { root = fixture }) -- second popup stays quiet
    assert.are.equal(n, #notes)
  end)
end)

describe('complete.auto_popup (M10.2)', function()
  local prev_buf, scratch
  local orig_mode, orig_pumvisible
  before_each(function()
    prev_buf = vim.api.nvim_get_current_buf()
    scratch = {}
    orig_mode, orig_pumvisible = vim.fn.mode, vim.fn.pumvisible
  end)
  after_each(function()
    vim.fn.mode, vim.fn.pumvisible = orig_mode, orig_pumvisible
    pcall(vim.api.nvim_set_current_buf, prev_buf)
    for _, b in ipairs(scratch) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end)

  local function use_buf(lines)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(scratch, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  it('declines outside insert mode, however open the context', function()
    use_buf({ '[[ml' })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    local fired = 0
    assert.is_false(complete.auto_popup(function()
      fired = fired + 1
    end))
    assert.are.equal(0, fired)
  end)

  it('fires the trigger once for an open context in insert mode', function()
    vim.fn.mode = function()
      return 'i'
    end
    use_buf({ 'see #ml' })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    local fired = 0
    assert.is_true(complete.auto_popup(function()
      fired = fired + 1
    end))
    assert.are.equal(1, fired)
  end)

  it('declines with no context or a visible popup', function()
    vim.fn.mode = function()
      return 'i'
    end
    use_buf({ '- plain' })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    local fired = 0
    local spy = function()
      fired = fired + 1
    end
    assert.is_false(complete.auto_popup(spy))
    use_buf({ '[[ml' })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    vim.fn.pumvisible = function()
      return 1
    end
    assert.is_false(complete.auto_popup(spy))
    assert.are.equal(0, fired)
  end)
end)

describe('complete.refresh (M10.6)', function()
  local config = require('logseq.config')
  local prev_buf, saved_g
  local orig_mode, orig_pumvisible, orig_complete, orig_feedkeys
  local scratch, dirs
  local completed, fed
  before_each(function()
    prev_buf = vim.api.nvim_get_current_buf()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    scratch, dirs = {}, {}
    completed, fed = nil, {}
    orig_mode, orig_pumvisible = vim.fn.mode, vim.fn.pumvisible
    orig_complete, orig_feedkeys = vim.fn.complete, vim.api.nvim_feedkeys
    vim.fn.mode = function()
      return 'i'
    end
    vim.fn.pumvisible = function()
      return 1
    end
    vim.fn.complete = function(col, items)
      completed = { col = col, items = items }
    end
    vim.api.nvim_feedkeys = function(keys, _, _)
      table.insert(fed, keys)
    end
    complete._last_refresh = nil
  end)
  after_each(function()
    vim.fn.mode, vim.fn.pumvisible = orig_mode, orig_pumvisible
    vim.fn.complete = orig_complete
    vim.api.nvim_feedkeys = orig_feedkeys
    complete._last_refresh = nil
    pcall(vim.api.nvim_set_current_buf, prev_buf)
    for _, b in ipairs(scratch) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    for _, d in ipairs(dirs) do
      vim.fn.delete(d, 'rf')
    end
    vim.g.logseq = saved_g
    config._reset()
  end)

  -- Temp graph with a Theme / Theme Song / Bathe Me / Zebra spread, the
  -- first page open with `line` as its only line and the cursor at EOL.
  local function theme_buf(line)
    local root = vim.fn.tempname()
    table.insert(dirs, root)
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    for _, title in ipairs({ 'Theme', 'Theme Song', 'Bathe Me', 'Zebra' }) do
      vim.fn.writefile({ '- nothing linked here' }, root .. '/pages/' .. title .. '.md')
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/pages/Theme.md'))
    table.insert(scratch, vim.api.nvim_get_current_buf())
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
    vim.api.nvim_win_set_cursor(0, { 1, #line })
  end

  local function words()
    local out = {}
    for _, item in ipairs(completed.items) do
      table.insert(out, item.word)
    end
    return out
  end

  it('declines with no popup or outside insert mode', function()
    theme_buf('[[theme')
    vim.fn.pumvisible = function()
      return 0
    end
    assert.is_false(complete.refresh())
    vim.fn.pumvisible = function()
      return 1
    end
    vim.fn.mode = function()
      return 'n'
    end
    assert.is_false(complete.refresh())
    assert.is_nil(completed)
    assert.are.same({}, fed)
  end)

  it('replaces the menu with the narrowed case-insensitive list', function()
    theme_buf('[[theme') -- lowercase: the builtin filter would not narrow
    assert.is_true(complete.refresh())
    assert.are.equal(3, completed.col) -- 1-based prefix col, after `[[`
    assert.are.same({ 'Theme', 'Theme Song', 'Bathe Me' }, words())
    for _, item in ipairs(completed.items) do
      assert.are.equal('● page', item.menu)
    end
    assert.are.same({}, fed) -- replaced, never dismissed
  end)

  it('dismisses when nothing matches', function()
    theme_buf('[[zxq')
    assert.is_true(complete.refresh())
    assert.is_nil(completed)
    assert.are.equal(1, #fed) -- one <C-e> abort, text untouched
  end)

  it('dismisses once the brackets close', function()
    theme_buf('[[Theme]]')
    assert.is_true(complete.refresh())
    assert.is_nil(completed)
    assert.are.equal(1, #fed)
  end)

  it('ignores its own replace instead of looping', function()
    theme_buf('[[theme')
    assert.is_true(complete.refresh())
    completed, fed = nil, {}
    assert.is_false(complete.refresh()) -- same line+cursor: no work
    assert.is_nil(completed)
    assert.are.same({}, fed)
  end)

  it('narrows manually opened menus too (no completion_auto gate)', function()
    config.setup({ completion_auto = false })
    theme_buf('[[theme')
    assert.is_true(complete.refresh())
    assert.are.same({ 'Theme', 'Theme Song', 'Bathe Me' }, words())
  end)
end)
