(.agents // []) as $agents
| def n(state): $agents | map(select(.state == state)) | length;
[
  [n("needs_input"), "!", "needs you", "255;152;90"],
  [n("errored"), "×", "errored", "255;56;139"],
  [n("working"), "◐", "working", "0;164;255"],
  [n("idle"), "○", "idle", "133;131;146"],
  [n("done"), "✓", "done", "0;255;178"],
  [n("unknown"), "□", "unknown", "133;131;146"]
]
| map(select(.[0] > 0) | {color: .[3], text: " \(.[1]) \(.[0]) \(.[2]) "})
# TUIOS caps custom cells at 80 columns. Keep the usual separators unless
# each group's own padding must double as the gap to fit all six groups.
| (if ((map(.text | length) | add // 0) + (length - 1) * 3) > 80 then "" else " · " end) as $separator
| map("\u001b[38;2;\(.color)m\(.text)\u001b[0m")
| join($separator)
