local pack = require 'config.pack'

pack.add {
  pack.repo 'echasnovski/mini.files',
}

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
