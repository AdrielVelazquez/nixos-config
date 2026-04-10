local pack = require 'config.pack'

pack.add {
  pack.repo 'echasnovski/mini.icons',
}

require('mini.icons').setup {}

package.preload['nvim-web-devicons'] = function()
  require('mini.icons').mock_nvim_web_devicons()
  return package.loaded['nvim-web-devicons']
end
