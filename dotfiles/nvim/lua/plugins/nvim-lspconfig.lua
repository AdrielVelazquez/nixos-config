return {
  'neovim/nvim-lspconfig',
  dependencies = { 'saghen/blink.cmp' },
  opts = {
    servers = {
      terraformls = {},
      lua_ls = {},
      dartls = {},
      gopls = {
        settings = {
          analyses = {
            unusedparams = true,
            fieldalignment = true,
            inferTypeArgs = true,
          },
          staticcheck = true, -- Enable for advanced static analysis
          -- Add this for experimental inlay hints (if you want them)
          hints = {
            assignVariableTypes = true,
            compositeLiteralFields = true,
            compositeLiteralTypes = true,
            constantValues = true,
            functionTypeParameters = true,
            parameterNames = true,
            rangeVariableTypes = true,
          },
        },
      },
      -- basedpyright = {},
      -- ruff = {},
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
