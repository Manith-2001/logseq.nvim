--- M7.1 contract: tasks.parse_line() + tasks.scan().
--- M7.0 skeleton — red by design (parse_line/scan are stubs).
--- Hermetic: tmp graphs only, ambient vim.g.logseq sanitized.
local tasks = require('logseq.tasks')
local config = require('logseq.config')

describe('tasks.parse_line (M7.1)', function()
  it('parses a plain TODO block', function()
    local status, text = tasks.parse_line('- TODO Buy milk')
    assert.are.equal('TODO', status)
    assert.are.equal('Buy milk', text)
  end)

  it('parses tab-indented nested blocks', function()
    local status, text = tasks.parse_line('\t\t- DOING write code')
    assert.are.equal('DOING', status)
    assert.are.equal('write code', text)
  end)

  it('accepts * bullets and keeps priorities/links as text', function()
    local status, text = tasks.parse_line('* LATER [#A] call [[Mom]]')
    assert.are.equal('LATER', status)
    assert.are.equal('[#A] call [[Mom]]', text)
  end)

  it('parses NOW, WAIT, WAITING, IN-PROGRESS, DONE, CANCELLED, CANCELED', function()
    local markers = {
      'NOW',
      'WAIT',
      'WAITING',
      'IN-PROGRESS',
      'DONE',
      'CANCELLED',
      'CANCELED',
    }
    for _, marker in ipairs(markers) do
      local status, text = tasks.parse_line('- ' .. marker .. ' something')
      assert.are.equal(marker, status)
      assert.are.equal('something', text)
    end
  end)

  it('rejects lowercase markers (Logseq requires capitals)', function()
    assert.is_nil(tasks.parse_line('- todo not a task'))
    assert.is_nil(tasks.parse_line('- done not a task'))
  end)

  it('rejects blank text after the marker', function()
    assert.is_nil(tasks.parse_line('- TODO'))
    assert.is_nil(tasks.parse_line('- TODO   '))
  end)

  it('rejects plain bullets, headings, numbered lists, bad input', function()
    assert.is_nil(tasks.parse_line('- just a bullet'))
    assert.is_nil(tasks.parse_line('# TODO heading'))
    assert.is_nil(tasks.parse_line('1. TODO numbered'))
    assert.is_nil(tasks.parse_line(''))
    assert.is_nil(tasks.parse_line(nil))
    assert.is_nil(tasks.parse_line(42))
  end)
end)

describe('tasks.scan (M7.1)', function()
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

  local function tmpgraph()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    table.insert(tmps, root)
    return root
  end

  it('collects tasks with path, lnum, title, kind', function()
    local root = tmpgraph()
    vim.fn.writefile({ '- TODO Buy milk', '- plain', '\t- DONE paid' }, root .. '/pages/Errands.md')
    vim.fn.writefile({ '- NOW standup notes' }, root .. '/journals/2026_09_05.md')
    local found = tasks.scan(root)
    assert.are.equal(3, #found)
    -- Global DONE-last (PLAN M7): open first in file-then-line order, then
    -- DONE-group. File order is graph.list_pages() (title-sorted), so the
    -- journal ('2026_09_05' < 'Errands') leads the open group.
    assert.are.equal('NOW', found[1].status)
    assert.are.equal('standup notes', found[1].text)
    assert.are.equal(root .. '/journals/2026_09_05.md', found[1].path)
    assert.are.equal(1, found[1].lnum)
    assert.are.equal('2026_09_05', found[1].title)
    assert.are.equal('journal', found[1].kind)
    assert.are.equal('TODO', found[2].status)
    assert.are.equal('Buy milk', found[2].text)
    assert.are.equal(root .. '/pages/Errands.md', found[2].path)
    assert.are.equal(1, found[2].lnum)
    assert.are.equal('Errands', found[2].title)
    assert.are.equal('page', found[2].kind)
    assert.are.equal('DONE', found[3].status)
    assert.are.equal('paid', found[3].text)
    assert.are.equal(3, found[3].lnum)
    assert.are.equal('page', found[3].kind)
  end)

  it('sorts DONE-group last, file-then-line within groups', function()
    local root = tmpgraph()
    vim.fn.writefile(
      { '- DONE old', '- TODO fresh', '- CANCELLED nope' },
      root .. '/pages/Mixed.md'
    )
    local found = tasks.scan(root)
    assert.are.equal(3, #found)
    assert.are.equal('TODO', found[1].status)
    assert.are.equal(2, found[1].lnum)
    assert.are.equal('DONE', found[2].status)
    assert.are.equal('CANCELLED', found[3].status)
  end)

  it('ignores plain bullets and lowercase todo lines', function()
    local root = tmpgraph()
    vim.fn.writefile(
      { '- just a bullet', '- todo lowercase', '# heading' },
      root .. '/pages/Plain.md'
    )
    assert.are.same({}, tasks.scan(root))
  end)

  it('missing dirs scan as empty, never an error', function()
    local root = vim.fn.tempname() -- no pages/ or journals/ created
    table.insert(tmps, root)
    vim.fn.mkdir(root, 'p')
    assert.are.same({}, tasks.scan(root))
  end)
end)
