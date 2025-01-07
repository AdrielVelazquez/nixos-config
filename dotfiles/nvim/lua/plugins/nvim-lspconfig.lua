return {
  'neovim/nvim-lspconfig',
  dependencies = { 'saghen/blink.cmp' },
  opts = {
    servers = {
      lua_ls = {},
      gopls = {},
      ruff = {},
      basedpyright = {},
      zls = {},
      starlark_rust = {
        settings = {
          filetypes = { 'star', 'bzl', 'BUILD.bazel', 'drone.star' },
        },
      },
      nil_ls = {
        settings = {
          ['nil'] = {
            formatting = {
              command = { 'nixfmt' },
            },
          },
        },
      },
    },
  },
  config = function(_, opts)
    local lspconfig = require 'lspconfig'
    for server, config in pairs(opts.servers) do
      config.capabilities = require('blink.cmp').get_lsp_capabilities(config.capabilities)
      lspconfig[server].setup(config)
    end
  end,
}
