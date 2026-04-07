local pack = require 'config.pack'
local kitty_scrollback_spec = pack.repo('AdrielVelazquez/kitty-scrollback.nvim', {
  version = 'ripgrep-fzflua-file-on-disk',
})

-- Register the plugin spec up front so `vim.pack.update()` uses the fork source
-- even though kitty-scrollback itself is configured lazily later on.
pack.add({ kitty_scrollback_spec }, { load = false, confirm = false })

local load_lint = function()
  pack.run_once('nvim-lint', function()
    pack.add {
      pack.repo 'mfussenegger/nvim-lint',
    }

    local lint = require 'lint'
    lint.linters_by_ft = {
      markdown = { 'markdownlint' },
    }

    local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
      group = lint_augroup,
      callback = function()
        if vim.opt_local.modifiable:get() then
          lint.try_lint()
        end
      end,
    })

    if vim.opt_local.modifiable:get() then
      lint.try_lint()
    end
  end)
end

vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
  once = true,
  callback = load_lint,
})

local load_dap = function()
  pack.run_once('dap-suite', function()
    pack.add {
      pack.repo 'mfussenegger/nvim-dap',
      pack.repo 'rcarriga/nvim-dap-ui',
      pack.repo 'nvim-neotest/nvim-nio',
      pack.repo 'leoluz/nvim-dap-go',
      pack.repo 'theHamsta/nvim-dap-virtual-text',
    }

    require('nvim-dap-virtual-text').setup {}
    require('dap-go').setup {}

    local dap = require 'dap'
    local dapui = require 'dapui'

    dapui.setup {}
    dap.listeners.after.event_initialized.dapui_config = function()
      dapui.open {}
    end
    dap.listeners.before.event_terminated.dapui_config = function()
      dapui.close {}
    end
    dap.listeners.before.event_exited.dapui_config = function()
      dapui.close {}
    end
  end)
end

vim.keymap.set('n', '<leader>dB', function()
  load_dap()
  require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
end, { desc = 'Breakpoint Condition' })

vim.keymap.set('n', '<leader>db', function()
  load_dap()
  require('dap').toggle_breakpoint()
end, { desc = 'Toggle Breakpoint' })

vim.keymap.set('n', '<leader>dc', function()
  load_dap()
  require('dap').continue()
end, { desc = 'Run/Continue' })

vim.keymap.set('n', '<leader>da', function()
  load_dap()
  require('dap').continue { before = get_args }
end, { desc = 'Run with Args' })

vim.keymap.set('n', '<leader>dC', function()
  load_dap()
  require('dap').run_to_cursor()
end, { desc = 'Run to Cursor' })

vim.keymap.set('n', '<leader>dg', function()
  load_dap()
  require('dap').goto_()
end, { desc = 'Go to Line (No Execute)' })

vim.keymap.set('n', '<leader>di', function()
  load_dap()
  require('dap').step_into()
end, { desc = 'Step Into' })

vim.keymap.set('n', '<leader>dj', function()
  load_dap()
  require('dap').down()
end, { desc = 'Down' })

vim.keymap.set('n', '<leader>dk', function()
  load_dap()
  require('dap').up()
end, { desc = 'Up' })

vim.keymap.set('n', '<leader>dl', function()
  load_dap()
  require('dap').run_last()
end, { desc = 'Run Last' })

vim.keymap.set('n', '<leader>do', function()
  load_dap()
  require('dap').step_out()
end, { desc = 'Step Out' })

vim.keymap.set('n', '<leader>dO', function()
  load_dap()
  require('dap').step_over()
end, { desc = 'Step Over' })

vim.keymap.set('n', '<leader>dP', function()
  load_dap()
  require('dap').pause()
end, { desc = 'Pause' })

vim.keymap.set('n', '<leader>dr', function()
  load_dap()
  require('dap').repl.toggle()
end, { desc = 'Toggle REPL' })

vim.keymap.set('n', '<leader>ds', function()
  load_dap()
  require('dap').session()
end, { desc = 'Session' })

vim.keymap.set('n', '<leader>dt', function()
  load_dap()
  require('dap').terminate()
end, { desc = 'Terminate' })

vim.keymap.set('n', '<leader>dw', function()
  load_dap()
  require('dap.ui.widgets').hover()
end, { desc = 'Widgets' })

vim.keymap.set('n', '<leader>du', function()
  load_dap()
  require('dapui').toggle {}
end, { desc = 'Dap UI' })

vim.keymap.set({ 'n', 'v' }, '<leader>de', function()
  load_dap()
  require('dapui').eval()
end, { desc = 'Eval' })

local load_silicon = function()
  pack.run_once('silicon', function()
    pack.add {
      pack.repo 'michaelrommel/nvim-silicon',
    }

    require('silicon').setup {
      font = 'GoMono Nerd Font=34',
    }
  end)
end

pack.proxy_command('Silicon', load_silicon, {
  nargs = '*',
  range = true,
  bang = true,
})

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
