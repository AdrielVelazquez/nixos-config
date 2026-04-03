local pack = require('config.pack')

pack.add({
  pack.repo('folke/which-key.nvim'),
  pack.repo('folke/flash.nvim'),
})

require('which-key').setup {
  icons = {
    mappings = vim.g.have_nerd_font,
    keys = vim.g.have_nerd_font and {} or {
      Up = '<Up> ',
      Down = '<Down> ',
      Left = '<Left> ',
      Right = '<Right> ',
      C = '<C-...> ',
      M = '<M-...> ',
      D = '<D-...> ',
      S = '<S-...> ',
      CR = '<CR> ',
      Esc = '<Esc> ',
      ScrollWheelDown = '<ScrollWheelDown> ',
      ScrollWheelUp = '<ScrollWheelUp> ',
      NL = '<NL> ',
      BS = '<BS> ',
      Space = '<Space> ',
      Tab = '<Tab> ',
      F1 = '<F1>',
      F2 = '<F2>',
      F3 = '<F3>',
      F4 = '<F4>',
      F5 = '<F5>',
      F6 = '<F6>',
      F7 = '<F7>',
      F8 = '<F8>',
      F9 = '<F9>',
      F10 = '<F10>',
      F11 = '<F11>',
      F12 = '<F12>',
    },
  },
  spec = {
    { '<leader>c', group = '[C]ode', mode = { 'n', 'x' } },
    { '<leader>d', group = '[D]ocument' },
    { '<leader>r', group = '[R]ename' },
    { '<leader>s', group = '[S]earch' },
    { '<leader>w', group = '[W]orkspace' },
    { '<leader>t', group = '[T]oggle' },
    { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
  },
}

require('flash').setup {}

vim.keymap.set({ 'n', 'x', 'o' }, 's', function()
  require('flash').jump()
end, { desc = 'Flash' })

vim.keymap.set({ 'n', 'x', 'o' }, 'S', function()
  require('flash').treesitter()
end, { desc = 'Flash Treesitter' })

vim.keymap.set('o', 'r', function()
  require('flash').remote()
end, { desc = 'Remote Flash' })

vim.keymap.set({ 'o', 'x' }, 'R', function()
  require('flash').treesitter_search()
end, { desc = 'Treesitter Search' })

vim.keymap.set('c', '<c-s>', function()
  require('flash').toggle()
end, { desc = 'Toggle Flash Search' })

local load_noice = function()
  pack.run_once('noice', function()
    pack.add({
      pack.repo('MunifTanjim/nui.nvim'),
      pack.repo('folke/noice.nvim'),
    })

    require('noice').setup {
      lsp = {
        signature = {
          enabled = false,
        },
      },
      routes = {
        {
          view = 'notify',
          filter = { event = 'msg_showmode' },
        },
        {
          filter = {
            event = 'msg_show',
            any = {
              { find = '%d+L, %d+B' },
              { find = '; after #%d+' },
              { find = '; before #%d+' },
            },
          },
          view = 'mini',
        },
      },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
      },
    }
  end)
end

vim.keymap.set('n', '<leader>sn', '<Nop>', { desc = '+noice' })
vim.keymap.set('c', '<S-Enter>', function()
  load_noice()
  require('noice').redirect(vim.fn.getcmdline())
end, { desc = 'Redirect Cmdline' })
vim.keymap.set('n', '<leader>snl', function()
  load_noice()
  require('noice').cmd('last')
end, { desc = 'Noice Last Message' })
vim.keymap.set('n', '<leader>snh', function()
  load_noice()
  require('noice').cmd('history')
end, { desc = 'Noice History' })
vim.keymap.set('n', '<leader>sna', function()
  load_noice()
  require('noice').cmd('all')
end, { desc = 'Noice All' })
vim.keymap.set('n', '<leader>snd', function()
  load_noice()
  require('noice').cmd('dismiss')
end, { desc = 'Dismiss All' })
vim.keymap.set('n', '<leader>snt', function()
  load_noice()
  require('noice').cmd('pick')
end, { desc = 'Noice Picker (Telescope/FzfLua)' })
vim.keymap.set({ 'i', 'n', 's' }, '<c-f>', function()
  load_noice()
  if not require('noice.lsp').scroll(4) then
    return '<c-f>'
  end
end, { desc = 'Scroll Forward', expr = true, silent = true })
vim.keymap.set({ 'i', 'n', 's' }, '<c-b>', function()
  load_noice()
  if not require('noice.lsp').scroll(-4) then
    return '<c-b>'
  end
end, { desc = 'Scroll Backward', expr = true, silent = true })

vim.schedule(load_noice)
