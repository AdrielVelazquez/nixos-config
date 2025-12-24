return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    build = ':TSUpdate',
    lazy = false,
    config = function()
      -- With the new main branch, treesitter highlighting is enabled via autocmd
      -- Parsers are installed via Nix (withAllGrammars), so no TSInstall needed
      vim.api.nvim_create_autocmd('FileType', {
        callback = function()
          -- Enable treesitter highlighting for the buffer
          pcall(vim.treesitter.start)
        end,
      })

      -- Optional: Enable treesitter-based indentation
      -- vim.api.nvim_create_autocmd('FileType', {
      --   callback = function()
      --     vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      --   end,
      -- })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    config = function()
      -- Textobjects: select
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

      -- Textobjects: move
      local ts_move = require('nvim-treesitter-textobjects.move')

      -- Next/previous function
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

      -- Next/previous class
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

      -- Next/previous conditional
      vim.keymap.set({ 'n', 'x', 'o' }, ']d', function()
        ts_move.goto_next_start('@conditional.outer', 'textobjects')
      end, { desc = 'Next conditional' })

      vim.keymap.set({ 'n', 'x', 'o' }, '[d', function()
        ts_move.goto_previous_start('@conditional.outer', 'textobjects')
      end, { desc = 'Previous conditional' })
    end,
  },
}
