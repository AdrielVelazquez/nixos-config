local pack = require 'config.pack'

local load_obsidian = function()
  pack.run_once('obsidian', function()
    pack.add {
      pack.repo('obsidian-nvim/obsidian.nvim', { version = pack.range '*' }),
    }

    require('obsidian').setup {
      legacy_commands = false,
      workspaces = {
        {
          name = 'personal',
          path = '~/.config/obsidian-vault/general',
        },
      },
      completion = {
        min_chars = 2,
      },
      daily_notes = {
        folder = 'daily',
        date_format = '%Y-%m-%d',
      },
      open = {
        func = function(uri)
          vim.ui.open(uri)
        end,
      },
      picker = {
        name = 'fzf-lua',
        mappings = {
          new = '<C-x>',
          insert_link = '<C-l>',
        },
      },
    }
  end)
end

pack.proxy_command('Obsidian', load_obsidian, {
  nargs = '*',
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  once = true,
  callback = load_obsidian,
})

vim.keymap.set('n', '<leader>on', '<cmd>Obsidian new<cr>', { desc = 'New Obsidian note' })
vim.keymap.set('n', '<leader>oo', '<cmd>Obsidian open<cr>', { desc = 'Open Obsidian app' })
vim.keymap.set('n', '<leader>os', '<cmd>Obsidian search<cr>', { desc = 'Search notes' })
vim.keymap.set('n', '<leader>oq', '<cmd>Obsidian quick-switch<cr>', { desc = 'Quick switch' })
vim.keymap.set('n', '<leader>ol', '<cmd>Obsidian link<cr>', { desc = 'Link note' })
vim.keymap.set('n', '<leader>oL', '<cmd>Obsidian link-new<cr>', { desc = 'Link to new note' })
vim.keymap.set('n', '<leader>ob', '<cmd>Obsidian backlinks<cr>', { desc = 'Show backlinks' })
vim.keymap.set('n', '<leader>ot', '<cmd>Obsidian today<cr>', { desc = "Open today's note" })
vim.keymap.set('n', '<leader>oy', '<cmd>Obsidian yesterday<cr>', { desc = "Open yesterday's note" })
vim.keymap.set('n', '<leader>oT', '<cmd>Obsidian template<cr>', { desc = 'Insert template' })
vim.keymap.set('n', 'gf', function()
  if vim.bo.filetype == 'markdown' then
    load_obsidian()

    if require('obsidian').util.cursor_on_markdown_link() then
      return '<cmd>Obsidian follow-link<cr>'
    end
  end

  return 'gf'
end, { desc = 'Follow link', expr = true })
