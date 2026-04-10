local pack = require 'config.pack'

pack.add {
  pack.repo 'ibhagwan/fzf-lua',
}

do
  local fzf = require 'fzf-lua'
  local config = fzf.config
  local actions = fzf.actions

  config.defaults.keymap.fzf['ctrl-q'] = 'select-all+accept'
  config.defaults.keymap.fzf['ctrl-u'] = 'half-page-up'
  config.defaults.keymap.fzf['ctrl-d'] = 'half-page-down'
  config.defaults.keymap.fzf['ctrl-x'] = 'jump'
  config.defaults.keymap.fzf['ctrl-f'] = 'preview-page-down'
  config.defaults.keymap.fzf['ctrl-b'] = 'preview-page-up'
  config.defaults.keymap.builtin['<c-f>'] = 'preview-page-down'
  config.defaults.keymap.builtin['<c-b>'] = 'preview-page-up'

  local img_previewer
  for _, value in ipairs {
    { cmd = 'ueberzug', args = {} },
    { cmd = 'chafa', args = { '{file}', '--format=symbols' } },
    { cmd = 'viu', args = { '-b' } },
  } do
    if vim.fn.executable(value.cmd) == 1 then
      img_previewer = vim.list_extend({ value.cmd }, value.args)
      break
    end
  end

  local opts = {
    'default-title',
    fzf_colors = true,
    fzf_opts = {
      ['--no-scrollbar'] = true,
    },
    defaults = {
      formatter = 'path.dirname_first',
    },
    previewers = {
      builtin = {
        extensions = {
          ['png'] = img_previewer,
          ['jpg'] = img_previewer,
          ['jpeg'] = img_previewer,
          ['gif'] = img_previewer,
          ['webp'] = img_previewer,
        },
        ueberzug_scaler = 'fit_contain',
      },
    },
    winopts = {
      width = 0.8,
      height = 0.8,
      row = 0.5,
      col = 0.5,
      preview = {
        scrollchars = { '┃', '' },
      },
    },
    files = {
      cwd_prompt = false,
      actions = {
        ['alt-i'] = { actions.toggle_ignore },
        ['alt-h'] = { actions.toggle_hidden },
      },
    },
    grep = {
      actions = {
        ['alt-i'] = { actions.toggle_ignore },
        ['alt-h'] = { actions.toggle_hidden },
      },
    },
    lsp = {
      symbols = {
        symbol_hl = function(symbol)
          return 'TroubleIcon' .. symbol
        end,
        symbol_fmt = function(symbol)
          return symbol:lower() .. '\t'
        end,
        child_prefix = false,
      },
      code_actions = {
        previewer = vim.fn.executable 'delta' == 1 and 'codeaction_native' or nil,
      },
    },
  }

  if opts[1] == 'default-title' then
    local function fix(value)
      value.prompt = value.prompt ~= nil and ' ' or nil
      for _, child in pairs(value) do
        if type(child) == 'table' then
          fix(child)
        end
      end
      return value
    end

    opts = vim.tbl_deep_extend('force', fix(require 'fzf-lua.profiles.default-title'), opts)
    opts[1] = nil
  end

  fzf.setup(opts)
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'fzf',
  callback = function(event)
    vim.keymap.set('t', '<c-j>', '<c-j>', { buffer = event.buf, nowait = true })
    vim.keymap.set('t', '<c-k>', '<c-k>', { buffer = event.buf, nowait = true })
  end,
})

local symbols_filter

vim.keymap.set('n', '<leader>,', '<cmd>FzfLua buffers sort_mru=true sort_lastused=true<cr>', { desc = 'Switch Buffer' })
vim.keymap.set('n', '<leader>:', '<cmd>FzfLua command_history<cr>', { desc = 'Command History' })
vim.keymap.set('n', '<leader>sb', '<cmd>FzfLua buffers sort_mru=true sort_lastused=true<cr>', { desc = 'Buffers' })
vim.keymap.set('n', '<leader>sf', '<cmd>FzfLua files<cr>', { desc = 'Find Files (Root Dir)' })
vim.keymap.set('n', '<leader>fg', '<cmd>FzfLua git_files<cr>', { desc = 'Find Files (git-files)' })
vim.keymap.set('n', '<leader>sr', '<cmd>FzfLua oldfiles<cr>', { desc = 'Recent' })
vim.keymap.set('n', '<leader>gc', '<cmd>FzfLua git_commits<cr>', { desc = 'Commits' })
vim.keymap.set('n', '<leader>gs', '<cmd>FzfLua git_status<cr>', { desc = 'Status' })
vim.keymap.set('n', '<leader>s"', '<cmd>FzfLua registers<cr>', { desc = 'Registers' })
vim.keymap.set('n', '<leader>sa', '<cmd>FzfLua autocmds<cr>', { desc = 'Auto Commands' })
vim.keymap.set('n', '<leader>/', '<cmd>FzfLua grep_curbuf<cr>', { desc = 'Buffer' })
vim.keymap.set('n', '<leader>sc', '<cmd>FzfLua command_history<cr>', { desc = 'Command History' })
vim.keymap.set('n', '<leader>sC', '<cmd>FzfLua commands<cr>', { desc = 'Commands' })
vim.keymap.set('n', '<leader>sd', '<cmd>FzfLua diagnostics_document<cr>', { desc = 'Document Diagnostics' })
vim.keymap.set('n', '<leader>sD', '<cmd>FzfLua diagnostics_workspace<cr>', { desc = 'Workspace Diagnostics' })
vim.keymap.set('n', '<leader>sg', '<cmd>FzfLua live_grep<cr>', { desc = 'Grep (Root Dir)' })
vim.keymap.set('n', '<leader>sh', '<cmd>FzfLua help_tags<cr>', { desc = 'Help Pages' })
vim.keymap.set('n', '<leader>sH', '<cmd>FzfLua highlights<cr>', { desc = 'Search Highlight Groups' })
vim.keymap.set('n', '<leader>sj', '<cmd>FzfLua jumps<cr>', { desc = 'Jumplist' })
vim.keymap.set('n', '<leader>sk', '<cmd>FzfLua keymaps<cr>', { desc = 'Key Maps' })
vim.keymap.set('n', '<leader>sl', '<cmd>FzfLua loclist<cr>', { desc = 'Location List' })
vim.keymap.set('n', '<leader>sM', '<cmd>FzfLua man_pages<cr>', { desc = 'Man Pages' })
vim.keymap.set('n', '<leader>sm', '<cmd>FzfLua marks<cr>', { desc = 'Jump to Mark' })
vim.keymap.set('n', '<leader>sR', '<cmd>FzfLua resume<cr>', { desc = 'Resume' })
vim.keymap.set('n', '<leader>sq', '<cmd>FzfLua quickfix<cr>', { desc = 'Quickfix List' })
vim.keymap.set('n', '<leader>uC', '<cmd>FzfLua colorschemes<cr>', { desc = 'Colorscheme with Preview' })
vim.keymap.set('n', '<leader>ss', function()
  require('fzf-lua').lsp_document_symbols {
    regex_filter = symbols_filter,
  }
end, { desc = 'Goto Symbol' })
vim.keymap.set('n', '<leader>sS', function()
  require('fzf-lua').lsp_live_workspace_symbols {
    regex_filter = symbols_filter,
  }
end, { desc = 'Goto Symbol (Workspace)' })
