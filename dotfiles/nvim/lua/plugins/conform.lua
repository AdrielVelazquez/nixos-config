return {
  'stevearc/conform.nvim',
  config = function()
    local conform = require 'conform'
    conform.setup {
      formatters_by_ft = {
        go = { 'gofumpt' },
        nix = { 'nixfmt' },
        python = { 'ruff_format' },
        lua = { 'stylua' },
      },
      format_on_save = {
        lsp_fallback = true,
        async = false,
        timeout_ms = 500,
      },
    }

    -- vim.api.nvim_create_autocmd('BufWritePre', {
    --   pattern = { '*' },
    --   callback = function()
    --     conform.format { async = false, lsp_fallback = true }
    --   end,
    -- })
    -- <leader>cf -> Format current buffer using conform
    vim.keymap.set('n', '<leader>cf', function()
      -- Call conform's format function
      -- async = true makes it non-blocking
      -- lsp_fallback = true allows using LSP formatter if conform doesn't find one
      require('conform').format { async = true, lsp_fallback = true }
    end, { desc = 'Format current buffer [C]onform [F]ormat' })
  end,
}
