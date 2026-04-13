local ts_textobjects = require 'config.treesitter_textobjects'

ts_textobjects.setup()

vim.api.nvim_create_autocmd('FileType', {
  callback = function()
    pcall(vim.treesitter.start)
  end,
})

do
  local select_maps = {
    ['af'] = '@function.outer',
    ['if'] = '@function.inner',
    ['ac'] = '@class.outer',
    ['ic'] = '@class.inner',
  }

  for keymap, query in pairs(select_maps) do
    vim.keymap.set({ 'x', 'o' }, keymap, function()
      ts_textobjects.select(query)
    end, { desc = 'Select ' .. query })
  end
end

do
  vim.keymap.set({ 'n', 'x', 'o' }, ']m', function()
    ts_textobjects.goto_next_start '@function.outer'
  end, { desc = 'Next function start' })

  vim.keymap.set({ 'n', 'x', 'o' }, ']M', function()
    ts_textobjects.goto_next_end '@function.outer'
  end, { desc = 'Next function end' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[m', function()
    ts_textobjects.goto_previous_start '@function.outer'
  end, { desc = 'Previous function start' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[M', function()
    ts_textobjects.goto_previous_end '@function.outer'
  end, { desc = 'Previous function end' })

  vim.keymap.set({ 'n', 'x', 'o' }, ']]', function()
    ts_textobjects.goto_next_start '@class.outer'
  end, { desc = 'Next class start' })

  vim.keymap.set({ 'n', 'x', 'o' }, '][', function()
    ts_textobjects.goto_next_end '@class.outer'
  end, { desc = 'Next class end' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[[', function()
    ts_textobjects.goto_previous_start '@class.outer'
  end, { desc = 'Previous class start' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[]', function()
    ts_textobjects.goto_previous_end '@class.outer'
  end, { desc = 'Previous class end' })

  vim.keymap.set({ 'n', 'x', 'o' }, ']d', function()
    ts_textobjects.goto_next_start '@conditional.outer'
  end, { desc = 'Next conditional' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[d', function()
    ts_textobjects.goto_previous_start '@conditional.outer'
  end, { desc = 'Previous conditional' })
end
