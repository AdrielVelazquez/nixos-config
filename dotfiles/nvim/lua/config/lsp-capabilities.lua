local capabilities = {
  textDocument = {
    foldingRange = {
      dynamicRegistration = false,
      lineFoldingOnly = true,
    },
  },
}

return require('blink.cmp').get_lsp_capabilities(capabilities)
