local pack = require 'config.pack'

local load_silicon = function()
  pack.run_once('silicon', function()
    pack.add {
      pack.repo 'michaelrommel/nvim-silicon',
    }

    require('silicon').setup {
      font = 'GoMono Nerd Font=34',
    }
  end)
end

pack.proxy_command('Silicon', load_silicon, {
  nargs = '*',
  range = true,
  bang = true,
})
