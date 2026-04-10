local pack = require 'config.pack'

pack.add {
  pack.repo 'lukas-reineke/indent-blankline.nvim',
}

require('ibl').setup {}
