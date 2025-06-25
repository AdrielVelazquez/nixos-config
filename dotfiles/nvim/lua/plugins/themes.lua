return {
  { 'rose-pine/neovim', name = 'rose-pine', priority = 1000 },
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  { 'folke/tokyonight.nvim', lazy = false, priority = 1000, opts = {} },
  { 'dgox16/oldworld.nvim', lazy = false, priority = 1000 },
  -- { 'kepano/flexoki-neovim', name = 'flexoki' },
  -- { 'adrielvelazquez/flexoki-neovim', lazy = false, priority = 1000, name = 'flexoki-adriel' },
  {
    'zenbones-theme/zenbones.nvim',
    -- Optionally install Lush. Allows for more configuration or extending the colorscheme
    -- If you don't want to install lush, make sure to set g:zenbones_compat = 1
    -- In Vim, compat mode is turned on as Lush only works in Neovim.
    dependencies = 'rktjmp/lush.nvim',
    lazy = false,
    priority = 1000,
    -- you can set set configuration options here
    -- config = function()
    --     vim.g.zenbones_darken_comments = 45
    --     vim.cmd.colorscheme('zenbones')
    -- end
  },
  {
    'rebelot/kanagawa.nvim',
    config = function()
      require('kanagawa').setup {
        keywordStyle = { italic = false },
        overrides = function(colors)
          local palette = colors.palette
          return {
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
    end,
  },
}
