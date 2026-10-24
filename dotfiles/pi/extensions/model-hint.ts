// Shows a dim hint under each assistant turn naming the model that produced
// it, and flags when it differs from the previous turn. Entries are durable
// but never sent to the LLM.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

interface HintData {
	model: string;
	previous?: string;
}

export default function (pi: ExtensionAPI) {
	let last: string | undefined;

	pi.on("session_start", async (_event, ctx) => {
		last = undefined;
		for (const entry of ctx.sessionManager.getEntries() as any[]) {
			if (entry.type === "custom" && entry.customType === "model-hint") {
				last = entry.data?.model;
			}
		}
	});

	pi.registerEntryRenderer<HintData>("model-hint", (entry, _opts, theme) => {
		const d = entry.data;
		if (!d) return new Text("", 0, 0);
		const text = d.previous
			? `↳ ${d.model}  (switched from ${d.previous})`
			: `↳ ${d.model}`;
		return new Text(theme.fg(d.previous ? "warning" : "dim", text), 1, 0);
	});

	pi.on("turn_end", async (event) => {
		const m = event.message as any;
		if (m?.role !== "assistant" || !m.model) return;
		const model = `${m.provider ?? "?"}/${m.model}`;
		const previous = last && last !== model ? last : undefined;
		last = model;
		pi.appendEntry<HintData>("model-hint", { model, previous });
	});
}
