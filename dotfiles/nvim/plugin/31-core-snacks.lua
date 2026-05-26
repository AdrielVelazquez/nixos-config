local pack = require 'config.pack'

pack.add {
  pack.repo 'folke/snacks.nvim',
}

local function is_in_current_git_root(file)
  local root = Snacks.git.get_root(vim.fn.getcwd())
  return root ~= nil and Snacks.git.get_root(file) == root
end

require('snacks').setup {
  bigfile = { enabled = true },
  toggle = {
    map = vim.keymap.set,
    which_key = true,
    notify = true,
  },
  dashboard = {
    width = 100,
    sections = {
      { section = 'header' },
      {
        icon = ' ',
        title = 'Recently Opened in Current Git Directory',
        section = 'recent_files',
        indent = 2,
        padding = 1,
        filter = is_in_current_git_root,
      },
      {
        icon = ' ',
        title = 'Recently Opened in General',
        section = 'recent_files',
        indent = 2,
        padding = 1,
      },
      { icon = ' ', title = 'Projects', section = 'projects', indent = 2, padding = 1 },
    },
  },
}
