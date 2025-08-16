return {
  'dmtrKovalenko/fff.nvim',
  build = 'nix run .#release',
  opts = {
    layout = {
      prompt_position = 'top', -- Position of prompt ('top' or 'bottom')
    },
  },
  keys = {
    {
      '<leader>sf', -- try it if you didn't it is a banger keybinding for a picker
      function()
        require('fff').find_files() -- or find_in_git_root() if you only want git files
      end,
      desc = 'Open file picker',
    },
    {
      '<leader>fg', -- try it if you didn't it is a banger keybinding for a picker
      function()
        require('fff').find_in_git_root() -- or find_in_git_root() if you only want git files
      end,
      desc = 'Open file picker',
    },
  },
}
