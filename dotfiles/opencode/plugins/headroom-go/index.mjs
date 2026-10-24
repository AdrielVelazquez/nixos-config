// Native OpenCode v2 provider adapter that routes OpenCode Go's
// OpenAI-compatible models through the loopback Headroom proxy.
// Anthropic, Responses, and Gemini models keep their direct gateway path.
export default {
  id: "local.headroom.opencode-go",
  async setup(context) {
    const upstream = new URL(context.options.upstreamBaseURL);
    const proxy = new URL(process.env.HEADROOM_PROXY_URL || context.options.proxyURL);
    if (!['127.0.0.1', 'localhost', '[::1]'].includes(proxy.hostname)) {
      throw new Error("Headroom must use a loopback proxy URL");
    }
    const baseURL = `${proxy.origin}/v1`;
    const upstreamPath = upstream.pathname.replace(/\/+$/, "");
    const registration = await context.provider.transform((editor) => {
      const record = editor.get("opencode-go");
      if (!record) return;
      const providerHeaders = record.provider.headers ?? {};
      for (const [id, model] of record.models) {
        const pkg = model.package || record.provider.package;
        if (pkg !== "@opencode/ai/providers/openai-compatible") continue;
        editor.models.update("opencode-go", id, (draft) => {
          // Model-level headers must not drop the provider's organization header.
          draft.settings = { ...draft.settings, baseURL };
          draft.headers = {
            ...providerHeaders,
            ...draft.headers,
            "x-headroom-base-url": upstream.origin,
            "x-headroom-original-path": `${upstreamPath}/chat/completions`,
          };
          draft.transport = "http";
        });
      }
    });
    return async () => {
      await registration.dispose();
    };
  },
};
