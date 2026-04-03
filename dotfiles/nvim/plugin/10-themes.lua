local pack = require 'config.pack'

pack.add {
  pack.repo('rose-pine/neovim', { name = 'rose-pine' }),
  pack.repo('catppuccin/nvim', { name = 'catppuccin' }),
  pack.repo 'folke/tokyonight.nvim',
  pack.repo 'dgox16/oldworld.nvim',
  pack.repo 'zenbones-theme/zenbones.nvim',
  pack.repo 'rktjmp/lush.nvim',
  pack.repo 'rebelot/kanagawa.nvim',
  pack.repo 'nyoom-engineering/oxocarbon.nvim',
  pack.repo 'dasupradyumna/midnight.nvim',
  pack.repo('bluz71/vim-moonfly-colors', { name = 'moonfly' }),
  pack.repo 'scottmckendry/cyberdream.nvim',
  pack.repo '0xstepit/flow.nvim',
  pack.repo 'eldritch-theme/eldritch.nvim',
}

require('oldworld').setup {
  variant = 'oled',
}

require('kanagawa').setup {
  keywordStyle = { italic = false },
  colors = {
    theme = {
      all = {
        ui = {
          bg_gutter = 'none',
        },
      },
    },
  },
  overrides = function(colors)
    local palette = colors.palette

    return {
      Normal = { bg = '#000000' },
      NormalFloat = { bg = '#000000' },
      FloatBorder = { bg = '#000000' },
      NonText = { bg = '#000000' },
      TelescopeTitle = { bg = '#000000' },
      TelescopePromptNormal = { bg = '#000000' },
      TelescopeResultsNormal = { bg = '#000000' },
      String = { italic = true },
      Boolean = { fg = palette.dragonPink },
      Constant = { fg = palette.dragonPink },
      Identifier = { fg = palette.dragonBlue },
      Statement = { fg = palette.dragonBlue },
      Operator = { fg = palette.dragonGray2 },
      Keyword = { fg = palette.dragonRed },
      Function = { fg = palette.dragonGreen },
      Type = { fg = palette.dragonYellow },
      Special = { fg = palette.dragonOrange },
      ['@lsp.typemod.function.readonly'] = { fg = palette.dragonBlue },
      ['@variable.member'] = { fg = palette.dragonBlue },
    }
  end,
}

require('cyberdream').setup {
  transparent = true,
  borderless_telescope = false,
}

require('flow').setup {
  dark_theme = true,
  transparent = true,
  high_contrast = true,
}

require 'config.colorschemes'
