import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Markdown } from "@earendil-works/pi-tui";

// Pi 1.3.0 has no default prose/editor foreground hook. Keep this adapter
// limited to exported render methods; never mutate terminal colors or messages.
function restoreForeground(line: string, prefix: string): string {
  return prefix + line.replace(/\x1b\[([0-9;]*)m/g, (sequence, body: string) => {
    const codes = body === "" ? [0] : body.split(";").map(Number);
    let restore = false;
    for (let i = 0; i < codes.length; i++) {
      const code = codes[i];
      if (code === 0 || code === 39) restore = true;
      else if ((code >= 30 && code <= 37) || (code >= 90 && code <= 97)) restore = false;
      else if (code === 38 || code === 48) {
        if (code === 38) restore = false;
        i += codes[i + 1] === 2 ? 4 : codes[i + 1] === 5 ? 2 : 0;
      }
    }
    return sequence + (restore ? prefix : "");
  }) + "\x1b[39m";
}

const owners = new Map<object, ExtensionContext>();
type Render = (this: unknown, width: number) => string[];
const patches: { prototype: { render: Render }; original: Render; wrapped: Render }[] = [];
function install() {
  if (patches.length) return;
  for (const prototype of [Markdown.prototype, CustomEditor.prototype]) {
    const original = prototype.render;
    if (typeof original !== "function") continue;
    const wrapped = function (this: unknown, width: number) {
      const lines = original.call(this, width);
      const context = [...owners.values()].at(-1);
      const prefix = context?.ui.theme.fg("text", "\0").split("\0")[0];
      return prefix ? lines.map((line: string) => restoreForeground(line, prefix)) : lines;
    };
    patches.push({ prototype, original, wrapped });
    prototype.render = wrapped;
  }
}
export default function (pi: ExtensionAPI) {
  const owner = {};
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    owners.set(owner, ctx);
    install();
  });
  pi.on("session_shutdown", () => {
    owners.delete(owner);
    if (owners.size) return;
    for (const { prototype, original, wrapped } of patches) {
      if (prototype.render === wrapped) prototype.render = original;
    }
    patches.length = 0;
  });
}
