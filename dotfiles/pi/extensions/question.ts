import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { cancelledAnswers, type Answer } from "./question-core.ts";
import { QuestionCard } from "./question-ui.ts";

export default function (pi: ExtensionAPI) {
  const pending = new Set<AbortController>();
  pi.on("session_shutdown", () => { for (const controller of pending) controller.abort(); pending.clear(); });
  pi.registerTool({
    name: "question", label: "Ask the user", exposure: "model-only",
    description: "Ask for input, a decision or permission through blocking UI. Put the recommended option first; free-form input is always available.",
    parameters: Type.Object({ questions: Type.Array(Type.Object({
      header: Type.String({ maxLength: 30 }), question: Type.String(),
      multiple: Type.Optional(Type.Boolean()),
      options: Type.Array(Type.Object({ label: Type.String(), description: Type.String() })),
    }), { minItems: 1 }) }),
    executionMode: "sequential",
    renderShell: "self",
    renderCall(input, theme) {
      const questions = Array.isArray(input.questions) ? input.questions : [];
      const topics = questions.map(item => typeof item?.header === "string" ? item.header : "").filter(Boolean);
      return new Text(theme.fg("muted", "Question" + (topics.length ? " · " + topics.join(" · ") : "")), 2, 0);
    },
    renderResult(result, _options, theme, context) {
      if (context?.isError) return new Text(theme.fg("error", "Question failed · No answer submitted."), 2, 0);
      const answers = (result.details as { answers?: Answer[] } | undefined)?.answers;
      if (answers?.length && answers.every(item => item.cancelled)) return new Text(theme.fg("warning", "Question cancelled · No answer submitted. No permission granted."), 2, 0);
      return new Text(answers?.length ? answers.map(item => item.cancelled
        ? theme.fg("warning", "Question cancelled · No answer submitted.")
        : theme.fg("muted", item.question) + "\n" + theme.fg("success", "✓ ") + item.answer.join(" · ")).join("\n")
        : theme.fg("warning", "No answer submitted."), 2, 0);
    },
    async execute(_id, input, signal, _update, ctx) {
      if (!ctx.hasUI) throw new Error("A user decision requires interactive Pi or an RPC client with UI support");
      const controller = new AbortController();
      const abort = () => controller.abort();
      signal?.addEventListener("abort", abort, { once: true });
      if (signal?.aborted) abort();
      pending.add(controller);
      let dismiss: (() => void) | undefined;
      let answers: Answer[] | null = null;
      try {
        if (!controller.signal.aborted && ctx.mode === "tui") {
          answers = await ctx.ui.custom<Answer[] | null>((tui, theme, _keys, done) => {
            const card = new QuestionCard(tui, theme, input.questions, done);
            dismiss = () => card.cancel();
            controller.signal.addEventListener("abort", dismiss, { once: true });
            if (controller.signal.aborted) card.cancel();
            return card;
          });
        } else if (!controller.signal.aborted) {
          answers = [];
          for (const item of input.questions) {
            const selected = new Set<string>();
            let cancelled = false;
            while (!controller.signal.aborted) {
              const options = item.options.map(option => `${selected.has(option.label) ? "✓ " : ""}${option.label} — ${option.description}`);
              const choice = await ctx.ui.select(`${item.header}: ${item.question}`, [...options,
                "Type your own answer", ...(item.multiple ? ["Done"] : [])], { signal: controller.signal });
              if (controller.signal.aborted || choice === undefined) { cancelled = true; break; }
              if (choice === "Done") { if (selected.size) break; else continue; }
              if (choice === "Type your own answer") {
                const answer = await ctx.ui.input(item.question, undefined, { signal: controller.signal });
                if (controller.signal.aborted || answer === undefined) { cancelled = true; break; }
                if (!answer.trim()) continue;
                selected.add(answer.trim());
              } else {
                const label = item.options[options.indexOf(choice)]?.label;
                if (label === undefined) continue;
                if (selected.has(label)) selected.delete(label); else selected.add(label);
              }
              if (!item.multiple) break;
            }
            if (cancelled || controller.signal.aborted) { answers = null; break; }
            answers.push({ question: item.question, answer: [...selected] });
          }
        }
        if (controller.signal.aborted || !answers) answers = cancelledAnswers(input.questions);
        return { content: [{ type: "text", text: JSON.stringify({ answers }) }], details: { answers } };
      } finally {
        signal?.removeEventListener("abort", abort);
        if (dismiss) controller.signal.removeEventListener("abort", dismiss);
        pending.delete(controller);
      }
    },
  });
}
