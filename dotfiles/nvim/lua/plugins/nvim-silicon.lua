return {
  'michaelrommel/nvim-silicon',
  lazy = true,
  cmd = 'Silicon',
  config = function()
    require('silicon').setup {
      -- Configuration here, or leave empty to use defaults
      font = 'GoMono Nerd Font=34',
    }
  end,
}
