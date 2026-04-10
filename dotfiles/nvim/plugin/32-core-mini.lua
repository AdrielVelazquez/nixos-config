local pack = require 'config.pack'

pack.add {
  pack.repo 'echasnovski/mini.nvim',
}

require('mini.ai').setup { n_lines = 500 }

local statusline = require 'mini.statusline'
statusline.setup { use_icons = vim.g.have_nerd_font }
statusline.section_location = function()
  return '%2l:%-2v'
end

require('mini.animate').setup()
