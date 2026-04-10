local pack = require 'config.pack'

pack.add {
  pack.repo 'folke/snacks.nvim',
}

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
