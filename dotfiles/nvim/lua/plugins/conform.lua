return {
  'stevearc/conform.nvim',
  config = function()
    local conform = require 'conform'
    conform.setup {
      formatters_by_ft = {
        go = { 'gofumpt' },
        nix = { 'nixfmt' },
        python = { 'ruff' },
        lua = { 'stylua' },
      },
      format_on_save = {
        lsp_fallback = true,
        async = false,
        timeout_ms = 500,
      },
    }

    vim.api.nvim_create_autocmd('BufWritePre', {
      pattern = { '*.go', '*.nix', '*.py', '*.lua' },
      callback = function()
        conform.format { async = false, lsp_fallback = true }
      end,
    })
  end,
}
