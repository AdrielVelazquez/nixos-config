# StyledEditor decorates native lines but inherits unadjusted mouse hit testing.
# Translate the same horizontal geometry used by render() before delegation.
''
  substituteInPlace "$out/lib/pi-extensions/pi-omp-theme/dist/extensions/pi-omp-theme.ts" \
    --replace-fail \
      'handleInput(data) {' \
      '  handleMouse(event) {
    if (this.disposed) return;
    const style = this.styleFor(event.width);
    if (style === "native") return super.handleMouse(event);
    const side = this.frameKind(style) === "rounded" ? 1 : 0;
    const padding = this.paddingFor(event.width, style);
    const prompt = widthOf2(this.prompt(event.width)) + 1;
    const dropdown = this.autocompleteState && event.y >= this.renderedVisibleLineCount + 2;
    const offset = dropdown ? side : side + padding + prompt;
    const width = Math.max(1, event.width - side * 2 - (this.autocompleteState ? 0 : prompt + padding * 2));
    return super.handleMouse({ ...event, x: event.x - offset, width });
  }
  handleInput(data) {'
''
