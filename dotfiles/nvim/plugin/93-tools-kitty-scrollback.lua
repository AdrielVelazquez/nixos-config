local pack = require 'config.pack'

local kitty_scrollback_spec = pack.repo('AdrielVelazquez/kitty-scrollback.nvim', {
  version = 'ripgrep-fzflua-file-on-disk',
})

-- Register the plugin spec up front so `vim.pack.update()` uses the fork source
-- even though kitty-scrollback itself is configured lazily later on.
pack.add({ kitty_scrollback_spec }, { load = false, confirm = false })

local load_kitty_scrollback = function()
  pack.run_once('kitty-scrollback', function()
    require('kitty-scrollback').setup {
      {
        scrollback_buffer = {
          tempfile = {
            enabled = true,
          },
          paste_window = {
            yank_register_enabled = false,
          },
          status_window = {
            autoclose = false,
          },
        },
      },
    }
  end)
end

pack.proxy_command('KittyScrollbackGenerateKittens', load_kitty_scrollback, {
  nargs = '*',
})

pack.proxy_command('KittyScrollbackCheckHealth', load_kitty_scrollback, {
  nargs = '*',
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'KittyScrollbackLaunch',
  once = true,
  callback = function()
    load_kitty_scrollback()
    vim.schedule(function()
      vim.api.nvim_exec_autocmds('User', { pattern = 'KittyScrollbackLaunch' })
    end)
  end,
})
