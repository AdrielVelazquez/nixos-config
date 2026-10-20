local pack = require 'config.pack'

pack.add { pack.repo 'Tim4c/tuios-nvim-navigator' }

-- Keep these in step with tuios's terminal_focus_* keys (Alt+Super+arrows),
-- which Neovim reads as <M-D-...>.
require('tuios-nvim-navigator').setup {
  keymaps = {
    left = '<M-D-Left>',
    down = '<M-D-Down>',
    up = '<M-D-Up>',
    right = '<M-D-Right>',
  },
}
