import { appendFileSync } from "node:fs";
import { visibleWidth } from "@earendil-works/pi-tui";

// Observe, but never replace, the real visual owner's editor instance.
export default function (pi) {
  const record = value => appendFileSync(process.env.PI_PARITY_EVENTS, JSON.stringify(value) + "\n");
  if (process.env.PI_PARITY_BASE_URL) pi.registerProvider("fixture", {
    baseUrl: process.env.PI_PARITY_BASE_URL,
    apiKey: "synthetic-only",
    api: "openai-completions",
    models: ["primary", "small", "strong", "tiny", "vision"].map(id => ({
      id, name: id, reasoning: true, input: id === "vision" ? ["text", "image"] : ["text"],
      contextWindow: 200000, maxTokens: 4096,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    })),
  });
  let current, width = 120;
  const observed = new WeakSet();
  pi.on("session_start", (_event, ctx) => record({ startup: true, mode: ctx.mode, theme: ctx.ui.theme.name, model: ctx.model && `${ctx.model.provider}/${ctx.model.id}` }));
  pi.on("resources_discover", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    const factory = ctx.ui.getEditorComponent();
    if (!factory) throw new Error("Combined UI has no editor factory");
    ctx.ui.setEditorComponent((...args) => {
      current = factory(...args);
      if (!observed.has(current)) {
        observed.add(current);
        const render = current.render.bind(current);
        current.render = columns => {
          width = columns;
          const lines = render(columns);
          const widths = lines.map(visibleWidth);
          if (widths.some(value => value > columns)) record({ overflow: true, columns, widths, lines });
          return lines;
        };
      }
      return current;
    });
  });
  pi.registerShortcut("alt+z", { description: "Clear integration-test draft", handler: async ctx => ctx.ui.setEditorText("") });
  pi.registerShortcut("alt+g", { description: "Observe combined editor buffer and render", handler: async ctx => {
    if (!current) throw new Error("Combined editor instance was not observed");
    const lines = current.render(width);
    record({ buffer: ctx.ui.getEditorText(), lines, width, widths: lines.map(visibleWidth), cursor: current.getCursor(), model: ctx.model && `${ctx.model.provider}/${ctx.model.id}` });
  } });
  pi.on("tool_result", event => record({ tool: event.toolName }));
  pi.on("agent_settled", () => record({ settled: true }));
}
