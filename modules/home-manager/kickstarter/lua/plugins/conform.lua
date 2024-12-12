return {
  "stevearc/conform.nvim",
  config = function()
    local conform = require("conform")
    conform.setup({
      formatters_by_ft = {
        go = { "gofumpt" },
        nix = { "nixfmt" },
      },
    })

    vim.api.nvim_create_autocmd("BufWritePre", {
      pattern = "*.go",
      callback = function()
        conform.format({ async = false, lsp_fallback = true })
      end,
    })
  end,
}
