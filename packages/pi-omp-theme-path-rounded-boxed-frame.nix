# 1.0.26 ignores explicit rounded frames for boxed editors. Preserve boxed's
# standalone status ownership while using its existing rounded render branch.
# Removal gates and upstream filing note: docs/todo-fragments/ui.md.
''
  substituteInPlace "$out/lib/pi-extensions/pi-omp-theme/dist/extensions/pi-omp-theme.ts" \
    --replace-fail \
      'if (style === "boxed") return "boxed";' \
      'if (style === "boxed" && frame !== "rounded") return "boxed";'
''
