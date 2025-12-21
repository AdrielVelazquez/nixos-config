return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    branch = 'main',
    -- NOTE: Parsers are installed via Nix (nvim-treesitter.withAllGrammars)
    -- Do not use :TSUpdate or install() as they conflict with Nix-managed parsers
    config = function()
      -- Automatically activate treesitter features for any buffer with an available parser
      vim.api.nvim_create_autocmd('FileType', {
        pattern = '*',
        callback = function(args)
          local bufnr = args.buf
          local ft = vim.bo[bufnr].filetype

          -- Only enable if a parser exists for this filetype
          local lang = vim.treesitter.language.get_lang(ft) or ft
          local ok = pcall(vim.treesitter.language.inspect, lang)
          if not ok then
            return
          end

          -- Enable syntax highlighting
          vim.treesitter.start(bufnr, lang)
          -- Enable treesitter-based folding (but keep folds open by default)
          vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.wo[0][0].foldmethod = 'expr'
          vim.wo[0][0].foldlevel = 99
          -- Enable treesitter-based indentation
          vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    config = function()
      local ts_move = require('nvim-treesitter-textobjects.move')
      local ts_select = require('nvim-treesitter-textobjects.select')
      local ts_repeat = require('nvim-treesitter-textobjects.repeatable_move')

      -- Repeatable move keymaps (make ; and , work with treesitter moves)
      vim.keymap.set({ 'n', 'x', 'o' }, ';', ts_repeat.repeat_last_move_next)
      vim.keymap.set({ 'n', 'x', 'o' }, ',', ts_repeat.repeat_last_move_previous)
      -- Make f, F, t, T also repeatable with ; and ,
      vim.keymap.set({ 'n', 'x', 'o' }, 'f', ts_repeat.builtin_f_expr, { expr = true })
      vim.keymap.set({ 'n', 'x', 'o' }, 'F', ts_repeat.builtin_F_expr, { expr = true })
      vim.keymap.set({ 'n', 'x', 'o' }, 't', ts_repeat.builtin_t_expr, { expr = true })
      vim.keymap.set({ 'n', 'x', 'o' }, 'T', ts_repeat.builtin_T_expr, { expr = true })

      -- Move keymaps
      -- Next start
      vim.keymap.set({ 'n', 'x', 'o' }, ']m', function() ts_move.goto_next_start('@function.outer') end, { desc = 'Next function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']]', function() ts_move.goto_next_start('@class.outer') end, { desc = 'Next class start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']o', function() ts_move.goto_next_start('@loop.*') end, { desc = 'Next loop start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']s', function() ts_move.goto_next_start('@local.scope', 'locals') end, { desc = 'Next scope' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']z', function() ts_move.goto_next_start('@fold', 'folds') end, { desc = 'Next fold' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']d', function() ts_move.goto_next('@conditional.outer') end, { desc = 'Next conditional' })

      -- Next end
      vim.keymap.set({ 'n', 'x', 'o' }, ']M', function() ts_move.goto_next_end('@function.outer') end, { desc = 'Next function end' })
      vim.keymap.set({ 'n', 'x', 'o' }, '][', function() ts_move.goto_next_end('@class.outer') end, { desc = 'Next class end' })

      -- Previous start
      vim.keymap.set({ 'n', 'x', 'o' }, '[m', function() ts_move.goto_previous_start('@function.outer') end, { desc = 'Previous function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[[', function() ts_move.goto_previous_start('@class.outer') end, { desc = 'Previous class start' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[d', function() ts_move.goto_previous('@conditional.outer') end, { desc = 'Previous conditional' })

      -- Previous end
      vim.keymap.set({ 'n', 'x', 'o' }, '[M', function() ts_move.goto_previous_end('@function.outer') end, { desc = 'Previous function end' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[]', function() ts_move.goto_previous_end('@class.outer') end, { desc = 'Previous class end' })

      -- Select keymaps
      vim.keymap.set({ 'x', 'o' }, 'af', function() ts_select.select_textobject('@function.outer') end, { desc = 'Select outer function' })
      vim.keymap.set({ 'x', 'o' }, 'if', function() ts_select.select_textobject('@function.inner') end, { desc = 'Select inner function' })
      vim.keymap.set({ 'x', 'o' }, 'ac', function() ts_select.select_textobject('@class.outer') end, { desc = 'Select outer class' })
      vim.keymap.set({ 'x', 'o' }, 'ic', function() ts_select.select_textobject('@class.inner') end, { desc = 'Select inner class' })
    end,
  },
}
