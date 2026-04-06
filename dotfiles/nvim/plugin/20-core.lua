local pack = require 'config.pack'

pack.add {
  pack.repo 'echasnovski/mini.icons',
  pack.repo 'folke/snacks.nvim',
  pack.repo 'echasnovski/mini.nvim',
  pack.repo 'echasnovski/mini.files',
  pack.repo('echasnovski/mini.sessions', { version = pack.range '*' }),
  pack.repo 'gbprod/cutlass.nvim',
  pack.repo 'lukas-reineke/indent-blankline.nvim',
  pack.repo 'mg979/vim-visual-multi',
  pack.repo 'tpope/vim-sleuth',
  pack.repo 'lewis6991/gitsigns.nvim',
  pack.repo 'stevearc/conform.nvim',
}

require('mini.icons').setup {}
package.preload['nvim-web-devicons'] = function()
  require('mini.icons').mock_nvim_web_devicons()
  return package.loaded['nvim-web-devicons']
end

require('mini.ai').setup { n_lines = 500 }

local statusline = require 'mini.statusline'
statusline.setup { use_icons = vim.g.have_nerd_font }
statusline.section_location = function()
  return '%2l:%-2v'
end

require('mini.animate').setup()

require('mini.files').setup {
  windows = {
    preview = true,
    width_focus = 30,
    width_preview = 30,
  },
  mappings = {
    close = 'q',
    go_in = '<Right>',
    go_in_plus = 'L',
    go_out = '<Left>',
    go_out_plus = 'H',
    mark_goto = "'",
    mark_set = 'm',
    reset = '<BS>',
    reveal_cwd = '@',
    show_help = 'g?',
    synchronize = '=',
    trim_left = '<',
    trim_right = '>',
  },
  options = {
    use_as_default_explorer = true,
    use_icons = true,
  },
}

vim.keymap.set('n', '<leader>fm', function()
  require('mini.files').open(vim.api.nvim_buf_get_name(0), true)
end, { desc = 'Open mini.files (directory of current file)' })

vim.keymap.set('n', '<leader>fM', function()
  require('mini.files').open(vim.loop.cwd(), true)
end, { desc = 'Open mini.files (cwd)' })

do
  local show_dotfiles = true

  local filter_show = function()
    return true
  end

  local filter_hide = function(fs_entry)
    return not vim.startswith(fs_entry.name, '.')
  end

  local toggle_dotfiles = function()
    show_dotfiles = not show_dotfiles
    local new_filter = show_dotfiles and filter_show or filter_hide
    require('mini.files').refresh { content = { filter = new_filter } }
  end

  vim.api.nvim_create_autocmd('User', {
    pattern = 'MiniFilesBufferCreate',
    callback = function(args)
      vim.keymap.set('n', 'g.', toggle_dotfiles, { buffer = args.data.buf_id })
    end,
  })
end

require 'config.sessions'

require('snacks').setup {
  bigfile = { enabled = true },
  toggle = {
    map = vim.keymap.set,
    which_key = true,
    notify = true,
  },
  dashboard = {
    sections = {
      { section = 'header' },
      { icon = ' ', title = 'Recent Files', section = 'recent_files', indent = 2, padding = 1 },
      { icon = ' ', title = 'Projects', section = 'projects', indent = 2, padding = 1 },
    },
  },
}

require('cutlass').setup {
  cut_key = 'x',
}

require('ibl').setup {}

require('gitsigns').setup {
  on_attach = function(bufnr)
    local gitsigns = require 'gitsigns'

    local function map(mode, lhs, rhs, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, lhs, rhs, opts)
    end

    map('n', ']c', function()
      if vim.wo.diff then
        vim.cmd.normal { ']c', bang = true }
      else
        gitsigns.nav_hunk 'next'
      end
    end, { desc = 'Jump to next git [c]hange' })

    map('n', '[c', function()
      if vim.wo.diff then
        vim.cmd.normal { '[c', bang = true }
      else
        gitsigns.nav_hunk 'prev'
      end
    end, { desc = 'Jump to previous git [c]hange' })

    map('v', '<leader>hs', function()
      gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
    end, { desc = 'stage git hunk' })

    map('v', '<leader>hr', function()
      gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
    end, { desc = 'reset git hunk' })

    map('n', '<leader>hs', gitsigns.stage_hunk, { desc = 'git [s]tage hunk' })
    map('n', '<leader>hr', gitsigns.reset_hunk, { desc = 'git [r]eset hunk' })
    map('n', '<leader>hS', gitsigns.stage_buffer, { desc = 'git [S]tage buffer' })
    map('n', '<leader>hu', gitsigns.undo_stage_hunk, { desc = 'git [u]ndo stage hunk' })
    map('n', '<leader>hR', gitsigns.reset_buffer, { desc = 'git [R]eset buffer' })
    map('n', '<leader>hp', gitsigns.preview_hunk, { desc = 'git [p]review hunk' })
    map('n', '<leader>hb', gitsigns.blame_line, { desc = 'git [b]lame line' })
    map('n', '<leader>hd', gitsigns.diffthis, { desc = 'git [d]iff against index' })
    map('n', '<leader>hD', function()
      gitsigns.diffthis '@'
    end, { desc = 'git [D]iff against last commit' })
    map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
    map('n', '<leader>tD', gitsigns.toggle_deleted, { desc = '[T]oggle git show [D]eleted' })
  end,
}

require('conform').setup {
  formatters_by_ft = {
    dart = { 'dart_format' },
    go = { 'gofumpt' },
    nix = { 'nixfmt' },
    python = { 'ruff_format' },
    lua = { 'stylua' },
  },
  formatters = {
    -- `dart format` needs the real filename to pick up analysis_options.yaml.
    dart_format = {
      args = { 'format', '$FILENAME' },
      stdin = false,
    },
  },
  format_on_save = {
    lsp_fallback = true,
    async = false,
    timeout_ms = 500,
  },
}

vim.keymap.set('n', '<leader>cf', function()
  require('conform').format { async = true, lsp_fallback = true }
end, { desc = 'Format current buffer [C]onform [F]ormat' })
