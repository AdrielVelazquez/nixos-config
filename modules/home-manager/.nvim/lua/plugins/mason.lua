return {
  {
    "williamboman/mason.nvim",
    enabled = true,
    opts = {
      ensure_installed = {
        "cmakelang",
        "cmakelint",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "gofumpt",
        "goimports",
        "gopls",
        "hadolint",
        "json-lsp",
        "lua-language-server",
        "neocmakelsp",
        "prettier",
        "shfmt",
        "python-lsp-server",
        "jedi-language-server",
        "stylua",
        "terraform-ls",
        "tflint",
      },
    },
  },
  { "williamboman/mason-lspconfig.nvim", enabled = true },
  { "neovim/nvim-lspconfig" },
}
