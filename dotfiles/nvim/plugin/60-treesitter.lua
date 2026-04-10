local pack = require 'config.pack'

pack.add {
  pack.repo('nvim-treesitter/nvim-treesitter', { version = 'main' }),
  pack.repo('nvim-treesitter/nvim-treesitter-textobjects', { version = 'main' }),
}

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
      require('nvim-treesitter-textobjects.select').select_textobject(query, 'textobjects')
    end, { desc = 'Select ' .. query })
  end
end

do
  local ts_move = require 'nvim-treesitter-textobjects.move'

  vim.keymap.set({ 'n', 'x', 'o' }, ']m', function()
    ts_move.goto_next_start('@function.outer', 'textobjects')
  end, { desc = 'Next function start' })

  vim.keymap.set({ 'n', 'x', 'o' }, ']M', function()
    ts_move.goto_next_end('@function.outer', 'textobjects')
  end, { desc = 'Next function end' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[m', function()
    ts_move.goto_previous_start('@function.outer', 'textobjects')
  end, { desc = 'Previous function start' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[M', function()
    ts_move.goto_previous_end('@function.outer', 'textobjects')
  end, { desc = 'Previous function end' })

  vim.keymap.set({ 'n', 'x', 'o' }, ']]', function()
    ts_move.goto_next_start('@class.outer', 'textobjects')
  end, { desc = 'Next class start' })

  vim.keymap.set({ 'n', 'x', 'o' }, '][', function()
    ts_move.goto_next_end('@class.outer', 'textobjects')
  end, { desc = 'Next class end' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[[', function()
    ts_move.goto_previous_start('@class.outer', 'textobjects')
  end, { desc = 'Previous class start' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[]', function()
    ts_move.goto_previous_end('@class.outer', 'textobjects')
  end, { desc = 'Previous class end' })

  vim.keymap.set({ 'n', 'x', 'o' }, ']d', function()
    ts_move.goto_next_start('@conditional.outer', 'textobjects')
  end, { desc = 'Next conditional' })

  vim.keymap.set({ 'n', 'x', 'o' }, '[d', function()
    ts_move.goto_previous_start('@conditional.outer', 'textobjects')
  end, { desc = 'Previous conditional' })
end
