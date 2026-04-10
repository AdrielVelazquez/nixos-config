local pack = require 'config.pack'

pack.add {
  pack.repo 'gbprod/cutlass.nvim',
}

require('cutlass').setup {
  cut_key = 'x',
}
