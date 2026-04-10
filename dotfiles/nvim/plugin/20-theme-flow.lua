local pack = require 'config.pack'

pack.add {
  pack.repo '0xstepit/flow.nvim',
}

require('flow').setup {
  dark_theme = true,
  transparent = true,
  high_contrast = true,
}
