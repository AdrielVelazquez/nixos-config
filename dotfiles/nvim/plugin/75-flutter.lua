local pack = require 'config.pack'

pack.add {
  pack.repo 'nvim-flutter/flutter-tools.nvim',
}

require('flutter-tools').setup {
  widget_guides = {
    enabled = true,
  },
  lsp = {
    capabilities = require 'config.lsp-capabilities',
    settings = {
      completeFunctionCalls = true,
      renameFilesWithClasses = 'prompt',
      updateImportsOnRename = true,
    },
  },
}
