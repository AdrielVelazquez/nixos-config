import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "question", label: "Ask the user", exposure: "model-only",
    description: "Ask for input, a decision or permission through blocking UI. Put the recommended option first; free-form input is always available.",
    parameters: Type.Object({ questions: Type.Array(Type.Object({
      header: Type.String({ maxLength: 30 }), question: Type.String(),
      multiple: Type.Optional(Type.Boolean()),
      options: Type.Array(Type.Object({ label: Type.String(), description: Type.String() })),
    }), { minItems: 1 }) }),
    async execute(_id, input, _signal, _update, ctx) {
      if (!ctx.hasUI) throw new Error("A user decision requires interactive Pi or an RPC client with UI support");
      const answers = [];
      for (const item of input.questions) {
        const selected = new Set<string>();
        let cancelled = false;
        while (true) {
          const options = item.options.map(option => `${selected.has(option.label) ? "✓ " : ""}${option.label} — ${option.description}`);
          const choice = await ctx.ui.select(`${item.header}: ${item.question}`, [...options,
            "Type your own answer", ...(item.multiple ? ["Done"] : [])]);
          if (choice === undefined) { cancelled = true; break; }
          if (choice === "Done") break;
          if (choice === "Type your own answer") {
            const answer = await ctx.ui.input(item.question);
            if (answer === undefined) { cancelled = true; break; }
            selected.add(answer);
          } else {
            const label = item.options[options.indexOf(choice)]?.label;
            if (label === undefined) continue;
            if (selected.has(label)) selected.delete(label); else selected.add(label);
          }
          if (!item.multiple) break;
        }
        answers.push({ question: item.question, answer: [...selected], ...(cancelled ? { cancelled: true } : {}) });
      }
      return { content: [{ type: "text", text: JSON.stringify({ answers }) }], details: { answers } };
    },
  });
}
