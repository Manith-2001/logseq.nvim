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
