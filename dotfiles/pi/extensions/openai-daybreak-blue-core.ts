export const DAYBREAK_BLUE_PROVIDER = "openai-codex";
export const DAYBREAK_BLUE_ALIAS = "gpt-6-sol-daybreak-blue";
export const DAYBREAK_BLUE_PHYSICAL_MODEL = "gpt-6-sol";

// Never throws: Pi catches hook errors and would send the request without the flag.
export function daybreakBluePayload(
  selected: { provider: string; id: string },
  payload: unknown,
): Record<string, unknown> | undefined {
  if (selected.provider !== DAYBREAK_BLUE_PROVIDER || selected.id !== DAYBREAK_BLUE_ALIAS) return undefined;
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return undefined;
  const body = payload as Record<string, unknown>;
  if (body.model !== DAYBREAK_BLUE_PHYSICAL_MODEL) return undefined;
  return { ...body, access_programs: { cyber: "daybreak_blue" } };
}
