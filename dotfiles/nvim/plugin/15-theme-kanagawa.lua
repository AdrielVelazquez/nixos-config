local pack = require 'config.pack'

pack.add {
  pack.repo 'rebelot/kanagawa.nvim',
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
