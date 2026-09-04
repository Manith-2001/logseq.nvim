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
