{ palette }:
''
  tooltip,
  tooltip.background {
    background: alpha(${palette.background}, 0.96);
    border: 1px solid alpha(${palette.accent}, 0.35);
    border-radius: 12px;
    box-shadow: 0 10px 28px alpha(#000000, 0.35);
  }

  tooltip label {
    color: ${palette.foreground};
    padding: 6px 10px;
  }
''
