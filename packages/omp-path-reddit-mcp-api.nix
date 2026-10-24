{ omp }:
omp.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./patches/omp-reddit-mcp-api.patch ];
})
