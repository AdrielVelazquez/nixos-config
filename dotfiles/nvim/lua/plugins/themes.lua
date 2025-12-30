return {
  { 'rose-pine/neovim', name = 'rose-pine', priority = 1000 },
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  { 'folke/tokyonight.nvim', lazy = false, priority = 1000, opts = {} },
  {
    'dgox16/oldworld.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('oldworld').setup {
        variant = 'oled',
      }
    end,
  },
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
    lazy = false, -- Ensure it loads on startup if this is your main theme
    priority = 1000,
    config = function()
      require('kanagawa').setup {
        keywordStyle = { italic = false },

        -- 1. Remove the background from the gutter (line numbers) so it matches Normal
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
            -- 2. Force Pure Black Backgrounds (OLED Mode)
            Normal = { bg = '#000000' },
            NormalFloat = { bg = '#000000' },
            FloatBorder = { bg = '#000000' },
            NonText = { bg = '#000000' },
            -- Optional: Force Telescope to black if you use it
            TelescopeTitle = { bg = '#000000' },
            TelescopePromptNormal = { bg = '#000000' },
            TelescopeResultsNormal = { bg = '#000000' },

            -- 3. Your Existing Syntax Overrides (Preserved)
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

  -- OLED-friendly themes
  {
    'nyoom-engineering/oxocarbon.nvim',
    lazy = false,
    priority = 1000,
    -- Use with: vim.cmd 'colorscheme oxocarbon'
  },
  {
    'dasupradyumna/midnight.nvim',
    lazy = false,
    priority = 1000,
    -- Use with: vim.cmd 'colorscheme midnight'
  },
  {
    'bluz71/vim-moonfly-colors',
    name = 'moonfly',
    lazy = false,
    priority = 1000,
    -- Use with: vim.cmd 'colorscheme moonfly'
  },
  {
    'scottmckendry/cyberdream.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('cyberdream').setup {
        transparent = true,
        borderless_telescope = false,
      }
    end,
    -- Use with: vim.cmd 'colorscheme cyberdream'
  },
  {
    '0xstepit/flow.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('flow').setup {
        dark_theme = true,
        transparent = true,
        high_contrast = true,
      }
    end,
    -- Use with: vim.cmd 'colorscheme flow'
  },
  {
    'eldritch-theme/eldritch.nvim',
    lazy = false,
    priority = 1000,
    -- Use with: vim.cmd 'colorscheme eldritch'
  },
}
