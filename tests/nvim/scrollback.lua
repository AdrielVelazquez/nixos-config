-- A plain stdin buffer loses ANSI styling; the pager must render it, not show escapes.
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. '/dotfiles/nvim')
vim.g.terminal_color_1 = '#ff6578'
local function open_scrollback(red, last_index)
  -- Simulate replies at the terminal protocol boundary, not the highlighter.
  vim.schedule(function()
    local function reply(sequence)
      vim.api.nvim_exec_autocmds('TermResponse', { data = { sequence = sequence } })
    end
    for i = 0, last_index or 15 do
      reply(('\27]4;%d;rgb:%s\27\\'):format(i, i == 1 and (red or '9b9b/2828/1b1b') or '0000/0000/0000'))
    end
    reply '\27]10;rgb:f6f6/d7d7/5c5c\27\\'
    reply '\27]11;rgb:0000/0000/0000\27\\'
  end)
  require('config.scrollback').open()
end
local lines = { '\27[31mred\27[0m plain', '\27[38;2;12;34;56mRGB\27[0m', '❯ prompt' }
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
open_scrollback()
assert(
  vim.wait(1000, function()
    return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'red plain'
  end),
  'ANSI escapes must become styling, not visible text'
)
assert(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == 'RGB', 'truecolor escapes must be rendered')
assert(vim.api.nvim_buf_get_lines(0, 2, 3, false)[1] == '❯ prompt', 'preserve Unicode and line boundaries')
local marks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
local colors = {}
for _, mark in ipairs(marks) do
  local group = mark[4].hl_group
  if group then
    colors[mark[2]] = vim.api.nvim_get_hl(0, { name = group }).fg
  end
end
assert(colors[0] == 0x9b281b, 'indexed ANSI red must use the terminal palette, not Cyberdream')
assert(colors[1] == 0x0c2238, 'explicit RGB colors must remain unchanged')
assert(vim.g.terminal_color_1 == '#ff6578', 'reading the terminal palette must not change the Neovim theme')
local namespace = vim.api.nvim_get_namespaces()['scrollback-terminal']
assert(namespace, 'pager must apply the terminal foreground/background locally')
local normal = vim.api.nvim_get_hl(namespace, { name = 'Normal' })
assert(normal.fg == 0xf6d75c and normal.bg == 0, 'default text must match the terminal too')
assert(vim.bo.readonly and not vim.bo.modifiable, 'scrollback must remain read-only')
assert(vim.fn.mode() == 'n', 'pager must start in normal mode for searching and yanking')
assert(vim.fn.maparg('q', 'n') ~= '', 'q must close the pager')
local filename = vim.api.nvim_buf_get_name(0)
assert(filename ~= '' and vim.fn.filereadable(filename) == 1, 'fzf-lua grep_curbuf requires a named file on disk')
assert(vim.deep_equal(vim.fn.readfile(filename), { 'red plain', 'RGB', '❯ prompt' }), 'snapshot must contain rendered text, not ANSI escapes')
assert(vim.fn.getfperm(filename) == 'rw-------', 'scrollback snapshots must be private')
local matches = vim.fn.system { 'rg', '--no-config', '--line-number', '--column', 'RGB', filename }
assert(vim.v.shell_error == 0 and matches == '2:1:RGB\n', 'ripgrep matches must use the visible buffer line numbers')
local buffer = vim.api.nvim_get_current_buf()
local fzf = require 'fzf-lua'
fzf.setup {}
fzf.grep_curbuf { search = 'RGB', multiprocess = false, previewer = false, fzf_opts = { ['--filter'] = 'RGB' } }
assert(
  vim.wait(5000, function()
    return vim.api.nvim_get_current_buf() == buffer and vim.api.nvim_win_get_cursor(0)[1] == 2
  end, 10),
  'fzf-lua must jump to the selected line in the original scrollback buffer'
)
assert(vim.bo.readonly and not vim.bo.modifiable, 'fzf-lua must preserve the read-only pager')
assert(vim.fn.filereadable(filename) == 1, 'snapshot must survive opening and closing the picker')

vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep('x', 77) .. '\27[31mNEEDLE\27[0m' })
open_scrollback '12/34/56'
vim.wait(100)
assert(vim.fn.search('NEEDLE', 'cw') == 1, 'pager width must not insert line breaks that break search/yank')
marks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
assert(vim.api.nvim_get_hl(0, { name = marks[1][4].hl_group }).fg == 0x123456, 'query the current palette on every open')

-- Keep long captures intact, including the oldest lines.
vim.cmd.enew()
lines = { 'first line' }
for i = 1, 12000 do
  lines[#lines + 1] = 'line ' .. i
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
open_scrollback()
assert(
  vim.wait(1000, function()
    return vim.api.nvim_buf_get_lines(0, 12000, 12001, false)[1] == 'line 12000'
  end),
  'long scrollback must be rendered completely'
)
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'first line', 'retain oldest captured lines')

-- A broken highlighter must not leave the normal Neovim palette overwritten.
vim.cmd.enew()
local baleia = require 'baleia'
local setup = baleia.setup
baleia.setup = function()
  error 'fixture setup failure'
end
local ok = pcall(open_scrollback)
baleia.setup = setup
assert(not ok, 'the fixture must exercise a failed setup')
assert(vim.g.terminal_color_1 == '#ff6578', 'restore the theme even when colorizer setup fails')

-- An unsupported or slow terminal must not silently look like a matched palette.
vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '\27[31mred\27[0m' })
local notify, warning = vim.notify
vim.notify = function(message, level)
  if level == vim.log.levels.WARN then
    warning = message
  end
end
open_scrollback(nil, 14)
vim.notify = notify
assert(warning and warning:find 'terminal palette', 'warn clearly when a complete terminal palette is unavailable')
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'red', 'fallback must still be readable without ANSI escapes')
vim.cmd 'qa!'
