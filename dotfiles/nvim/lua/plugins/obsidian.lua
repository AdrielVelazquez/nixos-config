return {
  'obsidian-nvim/obsidian.nvim',
  version = '*', -- use latest release, remove to use latest commit
  ft = 'markdown',
  dependencies = {
    -- Required
    'nvim-lua/plenary.nvim',
    -- Required for picker
    'ibhagwan/fzf-lua',
    -- Optional: for markdown preview
    'nvim-treesitter/nvim-treesitter',
  },
  ---@module 'obsidian'
  ---@type obsidian.config
  opts = {
    legacy_commands = false, -- Use new command format: `Obsidian backlinks` instead of `ObsidianBacklinks`
    workspaces = {
      {
        name = 'personal',
        path = '~/.config/obsidian-vault/general',
      },
    },
    -- Completion auto-detects blink.cmp when installed
    -- Triggered by typing `[[` for wiki links, `[` for markdown links, or `#` for tags
    completion = {
      min_chars = 2,
    },
    -- Optional: daily notes
    daily_notes = {
      folder = 'daily',
      date_format = '%Y-%m-%d',
    },
    -- Open module configuration (replaces deprecated use_advanced_uri and open_app_foreground)
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
  },
  keys = {
    -- New command format: `Obsidian <subcommand>`
    { '<leader>on', '<cmd>Obsidian new<cr>', desc = 'New Obsidian note' },
    { '<leader>oo', '<cmd>Obsidian open<cr>', desc = 'Open Obsidian app' },
    { '<leader>os', '<cmd>Obsidian search<cr>', desc = 'Search notes' },
    { '<leader>oq', '<cmd>Obsidian quick-switch<cr>', desc = 'Quick switch' },
    { '<leader>ol', '<cmd>Obsidian link<cr>', desc = 'Link note' },
    { '<leader>oL', '<cmd>Obsidian link-new<cr>', desc = 'Link to new note' },
    { '<leader>ob', '<cmd>Obsidian backlinks<cr>', desc = 'Show backlinks' },
    { '<leader>ot', '<cmd>Obsidian today<cr>', desc = 'Open today\'s note' },
    { '<leader>oy', '<cmd>Obsidian yesterday<cr>', desc = 'Open yesterday\'s note' },
    { '<leader>oT', '<cmd>Obsidian template<cr>', desc = 'Insert template' },
    -- Follow link under cursor
    { 'gf', function()
      if require('obsidian').util.cursor_on_markdown_link() then
        return '<cmd>Obsidian follow-link<cr>'
      else
        return 'gf'
      end
    end, expr = true, desc = 'Follow link' },
  },
}
