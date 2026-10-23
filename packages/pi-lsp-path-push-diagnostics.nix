# pi-lsp 0.15.1 incorrectly gates automatic diagnostics on pull support.
# Keep the upstream version-aware push collector; only fix eligibility.
''
  patch -d "$out/node_modules/@ian-pascoe/pi-lsp" -p1 < ${./pi-lsp-path-push-diagnostics.patch}
''
