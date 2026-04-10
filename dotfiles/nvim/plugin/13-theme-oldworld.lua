local pack = require 'config.pack'

pack.add {
  pack.repo 'dgox16/oldworld.nvim',
}

require('oldworld').setup {
  variant = 'oled',
}
