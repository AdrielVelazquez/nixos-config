# pi-lsp 0.15.1 persists `/lsp enable|disable --global` by rewriting settings.json atomically
# beside its real path. A declaratively managed settings.json is read-only, so the write fails
# with EACCES. Global choices go to a writable lsp-enablement.json in the agent directory.
''
  patch -d "$out/node_modules/@ian-pascoe/pi-lsp" -p1 < ${./pi-lsp-path-writable-enablement.patch}
''
