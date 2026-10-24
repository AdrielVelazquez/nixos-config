# Pi omp/opencode parity: evaluation archive

Five independent evaluators ran real pi 1.3.0 in a PTY against a scripted local model on the user's actual terminal
(Ghostty "Mona Lisa" on #000000, Maple Mono NF). Labels: [E] executed, [C] read in code/docs, [H] hypothesis.
Paths inside the reports that start with `/tmp/pi-lab/` were session-local lab directories and no longer exist;
the screenshots that mattered are in `images/`.

| Report | Area | Verdict |
|---|---|---|
| `visuals-report.md` | UI plugins | `pi-omp-theme@1.0.26` closest to omp; `pi-tui-footer@1.4.2` simpler alternate; statuses need `placement: above` |
| `theme-report.md` | themes and code colors | `omp-reference` default, `omp-dark` alternate; prose stays terminal-yellow without a neutral-foreground adapter |
| `lsp-report.md` | LSP | `@ian-pascoe/pi-lsp@0.15.1` + 15-line push-diagnostics patch + status bridge |
| `ghost-report.md` | ghost-text word completion | no plugin qualifies; own extension mounted in `resources_discover` |
| `routing-report.md` | role routing | own dependency-free router on `registerVirtualModel`; 16 unit tests; `/models` screen |

Integrity strings quoted in these reports were not independently re-derived; the implementation recomputes every pin
with `nix store prefetch-file` and compares it with the registry.
