local pack = require 'config.pack'

pack.add {
  pack.repo 'scottmckendry/cyberdream.nvim',
}

require('cyberdream').setup {
  transparent = true,
  borderless_telescope = false,
}
