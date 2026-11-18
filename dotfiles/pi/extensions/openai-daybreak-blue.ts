import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  DAYBREAK_BLUE_ALIAS,
  DAYBREAK_BLUE_PHYSICAL_MODEL,
  DAYBREAK_BLUE_PROVIDER,
  daybreakBluePayload,
} from "./openai-daybreak-blue-core.ts";

// Adapted from matthew-warren/pi-reddit-daybreak-virtual-model@6939458, retargeted from openai to openai-codex.
export default function (pi: ExtensionAPI) {
  pi.registerVirtualModel({
    provider: DAYBREAK_BLUE_PROVIDER,
    id: DAYBREAK_BLUE_ALIAS,
    name: "GPT-6 Sol (Daybreak Blue)",
    thinkingLevels: ["off", "minimal", "low", "medium", "high", "xhigh", "max"],
    contextWindow: 272_000,
    maxTokens: 128_000,
    route(request, ctx) {
      const model = ctx.modelRegistry.find(DAYBREAK_BLUE_PROVIDER, DAYBREAK_BLUE_PHYSICAL_MODEL);
      if (!model) throw new Error(`${DAYBREAK_BLUE_PROVIDER}/${DAYBREAK_BLUE_PHYSICAL_MODEL} is unavailable`);
      return { model, thinkingLevel: request.thinkingLevel };
    },
  });

  pi.on("before_provider_request", (event, ctx) =>
    daybreakBluePayload({ provider: ctx.model?.provider ?? "", id: ctx.model?.id ?? "" }, event.payload),
  );
}
