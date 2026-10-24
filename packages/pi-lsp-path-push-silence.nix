# pi-lsp 0.15.1 spends the whole diagnostics window on every edit of a clean file
# whose push-only server stays silent, then reports that silence as a timeout.
''
  patch -d "$out/node_modules/@ian-pascoe/pi-lsp" -p1 < ${./pi-lsp-path-push-silence.patch}
''
