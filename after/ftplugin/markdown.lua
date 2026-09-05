-- after/ftplugin/markdown.lua — graph-scoped buffer opts (M3) plus
-- [[ ]] completion wiring (M10.2: buffer omnifunc + auto-popup).
-- Fires for every markdown buffer; applies only when the file lives
-- inside a Logseq graph. Detection is buffer-anchored (walk up from the
-- file itself), deliberately NOT config.graph_path: a global override must
-- not mark unrelated markdown files as graph pages.
-- Buffer-local only; never touches global options or keys.
local buf = vim.api.nvim_get_current_buf()
local name = vim.api.nvim_buf_get_name(buf)
if name == '' then
  return
end
local ok, graph = pcall(require, 'logseq.graph')
if not ok then
  return
end
local root = graph.find_root_from(name)
if not root then
  return
end
vim.b[buf].logseq_root = root
-- Logseq nests blocks with hard tabs (see PLAN.md §8.4); keep them literal
-- instead of expanding to spaces on indent.
vim.opt_local.expandtab = false
-- Buffer-local Logseq keys (M9, the documented exception to the
-- no-default-keys rule; user-removable via :nunmap <buffer>). Each key
-- is guarded independently: an existing map (user or otherwise) is never
-- clobbered, so partial user config still gets the remaining keys.
local function bufmap(lhs, fn, desc)
  if vim.fn.maparg(lhs, 'n') == '' then
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, desc = desc })
  end
end
bufmap('<CR>', function()
  require('logseq').smart_action()
end, 'Logseq: follow link, cycle task, or move down')
bufmap('[o', function()
  require('logseq').nav_link('prev')
end, 'Logseq: jump to previous link')
bufmap(']o', function()
  require('logseq').nav_link('next')
end, 'Logseq: jump to next link')

-- [[ ]] completion (M10.2): buffer-local omnifunc (manual <C-x><C-o>
-- always; auto-popup gated on completion_auto) plus an InsertCharPre
-- watcher that pops the menu while typing in an open context.
local complete_ok = pcall(require, 'logseq.complete')
if complete_ok then
  -- Popup safety (M10.5): Neovim's default completeopt pre-selects the
  -- first menu item AND writes it into the buffer the moment the menu
  -- opens. With the watcher firing on every keystroke that made typing
  -- inside [[ ]] impossible: the top match was re-inserted on each char
  -- and no input ever survived. Buffer-local noselect+noinsert keeps the
  -- menu advisory-only (pick with <C-n>/<C-p>, confirm, or keep typing
  -- to narrow); every other flag stays exactly as the user set it, and
  -- the global value is untouched.
  vim.opt_local.completeopt:append({ 'noselect', 'noinsert' })
  -- Never clobber a user omnifunc (LSP, blink, ...): take over only when
  -- unset or holding Neovim's stock markdown value. Stock
  -- $VIMRUNTIME/ftplugin/markdown.vim opens with `runtime!
  -- ftplugin/html.vim`, so every markdown buffer arrives with
  -- htmlcomplete#CompleteTags — "only when unset" would silently disable
  -- the feature on stock setups.
  local cur = vim.bo[buf].omnifunc
  if cur == '' or cur == 'htmlcomplete#CompleteTags' then
    vim.bo[buf].omnifunc = "v:lua.require'logseq.complete'.omnifunc"
  end
  -- Buffer-scoped autocmds die with the buffer; the per-event group
  -- checks keep a ftplugin re-source from stacking duplicate watchers.
  local grp = vim.api.nvim_create_augroup('LogseqComplete', { clear = false })
  if #vim.api.nvim_get_autocmds({ group = grp, buffer = buf, event = 'InsertCharPre' }) == 0 then
    vim.api.nvim_create_autocmd('InsertCharPre', {
      group = grp,
      buffer = buf,
      desc = 'Logseq: auto-popup [[ ]] completion',
      callback = function()
        -- A closing bracket ends the context (or a dismissal): popping
        -- the menu back open on `]` fights the keystroke, so the user
        -- can always type `]]` in peace.
        if vim.v.char == ']' then
          return
        end
        -- completion_auto is read at fire time, so mid-session toggles
        -- apply without re-sourcing. Deferred past the inserted char so
        -- find_start() sees the fresh line; rapid keystrokes queue
        -- several checks, but only the first fires: the rest see the
        -- visible popup and decline.
        if not require('logseq.config').get().completion_auto then
          return
        end
        vim.schedule(function()
          require('logseq.complete').auto_popup()
        end)
      end,
    })
  end
  -- Live narrowing (M10.6): while the menu is up, every keystroke
  -- re-ranks through the shared core and swaps the list in place, so
  -- typing `theme` leaves only case-insensitive matches instead of the
  -- builtin popup's own filtering. Deliberately NOT gated on
  -- completion_auto — a manually opened menu must narrow too — and
  -- loop-safe via the unchanged-state guard in complete.refresh().
  if #vim.api.nvim_get_autocmds({ group = grp, buffer = buf, event = 'CompleteChanged' }) == 0 then
    vim.api.nvim_create_autocmd('CompleteChanged', {
      group = grp,
      buffer = buf,
      desc = 'Logseq: live-narrow [[ ]] completion',
      callback = function()
        vim.schedule(function()
          require('logseq.complete').refresh()
        end)
      end,
    })
  end
end
