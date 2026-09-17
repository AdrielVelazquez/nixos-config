// Native OpenCode v2 provider adapter for the LLM Platform provider.
// Replayed after model discovery/refresh; credentials stay in the original plugin.
export default {
  id: "local.headroom.llm-platform",
  async setup(context) {
    const upstream = new URL(context.options.upstreamBaseURL);
    const proxy = new URL(process.env.HEADROOM_PROXY_URL || context.options.proxyURL);
    if (!['127.0.0.1', 'localhost', '[::1]'].includes(proxy.hostname)) {
      throw new Error("Headroom must use a loopback proxy URL");
    }
    const baseURL = `${proxy.origin}/v1`;
    const upstreamPath = upstream.pathname.replace(/\/+$/, "");
    const headers = {
      "x-client": "opencode",
      "x-headroom-base-url": upstream.origin,
    };
    const registration = await context.provider.transform((editor) => {
      const record = editor.get("llmplatform");
      if (!record) return;
      editor.update("llmplatform", (provider) => {
        provider.settings = { ...provider.settings, baseURL };
        provider.headers = { ...provider.headers, ...headers };
        provider.transport = "http";
      });
      for (const [id, model] of record.models) {
        const pkg = model.package || record.provider.package;
        const endpoint = pkg.endsWith("/responses") ? "/responses" : "/chat/completions";
        editor.models.update("llmplatform", id, (draft) => {
          draft.settings = { ...draft.settings, baseURL };
          draft.headers = {
            ...draft.headers,
            ...headers,
            "x-headroom-original-path": upstreamPath + endpoint,
          };
          draft.transport = "http";
        });
      }
    });
    return () => registration.dispose();
  },
};
