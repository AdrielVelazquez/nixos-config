local pack = require 'config.pack'

local load_noice = function()
  pack.run_once('noice', function()
    pack.add {
      pack.repo 'MunifTanjim/nui.nvim',
      pack.repo 'folke/noice.nvim',
    }

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
  require('noice').cmd 'last'
end, { desc = 'Noice Last Message' })
vim.keymap.set('n', '<leader>snh', function()
  load_noice()
  require('noice').cmd 'history'
end, { desc = 'Noice History' })
vim.keymap.set('n', '<leader>sna', function()
  load_noice()
  require('noice').cmd 'all'
end, { desc = 'Noice All' })
vim.keymap.set('n', '<leader>snd', function()
  load_noice()
  require('noice').cmd 'dismiss'
end, { desc = 'Dismiss All' })
vim.keymap.set('n', '<leader>snt', function()
  load_noice()
  require('noice').cmd 'pick'
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
