-- nvim-treesitter configuration for main branch (post-rewrite)
return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      -- Main branch uses a simpler setup
      require('nvim-treesitter').setup({
        -- Parsers are now installed via :TSInstall or Nix
        -- No ensure_installed option in main branch
      })

      -- Enable treesitter highlighting for all filetypes
      -- This replaces the old highlight = { enable = true }
      vim.api.nvim_create_autocmd('FileType', {
        pattern = '*',
        callback = function(args)
          -- Skip certain filetypes
          local ft = vim.bo[args.buf].filetype
          local skip = { 'help', 'alpha', 'dashboard', 'neo-tree', 'Trouble', 'lazy', 'mason' }
          if vim.tbl_contains(skip, ft) then
            return
          end

          -- Try to start treesitter, ignore if no parser
          pcall(vim.treesitter.start)
        end,
      })

      -- Set up treesitter-based indentation
      vim.api.nvim_create_autocmd('FileType', {
        pattern = '*',
        callback = function()
          pcall(function()
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end)
        end,
      })
    end,
  },

  -- Textobjects - uses nvim-treesitter.configs for setup (still works on main)
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      -- Textobjects still uses the configs-based setup
      require('nvim-treesitter.configs').setup({
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ['af'] = '@function.outer',
              ['if'] = '@function.inner',
              ['ac'] = '@class.outer',
              ['ic'] = '@class.inner',
              ['aa'] = '@parameter.outer',
              ['ia'] = '@parameter.inner',
            },
            selection_modes = {
              ['@parameter.outer'] = 'v',
              ['@function.outer'] = 'V',
              ['@class.outer'] = 'V',
            },
            include_surrounding_whitespace = true,
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              [']m'] = '@function.outer',
              [']]'] = '@class.outer',
            },
            goto_next_end = {
              [']M'] = '@function.outer',
              [']['] = '@class.outer',
            },
            goto_previous_start = {
              ['[m'] = '@function.outer',
              ['[['] = '@class.outer',
            },
            goto_previous_end = {
              ['[M'] = '@function.outer',
              ['[]'] = '@class.outer',
            },
          },
        },
      })
    end,
  },
}
