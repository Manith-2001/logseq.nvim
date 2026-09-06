-- Shared spec lifecycle (audit P4 #5): the graph/buffer/global-state
-- fixture mechanics duplicated across init_spec / view_spec /
-- graphall_spec. Feature-specific setup and assertions stay local to
-- each spec; this file owns restore-everything teardown only.
-- NB: must NOT be named *_spec.lua (plenary would run it as a spec).
local H = {}

H.config = require('logseq.config')
H.graph = require('logseq.graph')
H.tele = require('logseq.telescope')

function H.setup()
  H.notes = {}
  H.bufs = {}
  H.tmps = {}
  H.saved_cwd = vim.fn.getcwd()
  H.orig_notify = vim.notify
  H.orig_input = vim.ui.input
  H.saved_g = vim.g.logseq
  vim.g.logseq = nil
  H.config._reset()
  H.graph._set_state_file(vim.fn.tempname()) -- hermetic: no real active graph
  vim.notify = function(msg, level)
    table.insert(H.notes, { msg = msg, level = level })
  end
end

function H.teardown()
  vim.notify = H.orig_notify
  vim.ui.input = H.orig_input
  H.graph._set_state_file(nil)
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

-- Fresh tmp graph root with pages/ + journals/ dirs (+ optional pages files).
function H.tmpgraph(files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. '/pages', 'p')
  vim.fn.mkdir(root .. '/journals', 'p')
  for name, lines in pairs(files or {}) do
    vim.fn.writefile(lines, root .. '/pages/' .. name .. '.md')
  end
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

function H.buf_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

function H.find_line(buf, text)
  for i, line in ipairs(H.buf_lines(buf)) do
    if line == text then
      return i
    end
  end
  return nil
end

function H.contains(buf, text)
  return H.find_line(buf, text) ~= nil
end

return H
