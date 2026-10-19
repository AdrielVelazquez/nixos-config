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
        const gemini = pkg === "@opencode/ai/providers/google";
        const endpoint = pkg.endsWith("/responses") ? "/responses" : "/chat/completions";
        editor.models.update("llmplatform", id, (draft) => {
          // Native Gemini uses Headroom's unchanged-path passthrough, not its
          // OpenAI handlers. The pinned proxy does not compress this route.
          draft.settings = {
            ...draft.settings,
            baseURL: gemini ? `${proxy.origin}/v1/gemini` : baseURL,
          };
          draft.headers = {
            ...draft.headers,
            ...headers,
          };
          if (gemini) {
            delete draft.headers["x-headroom-original-path"];
          } else {
            draft.headers["x-headroom-original-path"] = upstreamPath + endpoint;
          }
          draft.transport = "http";
        });
      }
    });
    const signatureHook = await context.session.hook("http.request", async (event) => {
      if (!event.request.url.startsWith(`${proxy.origin}/v1/gemini/models/`)) return;
      // The provider's equivalent hook matches only the original gateway URL,
      // so preserve its unsigned-tool rewrite after routing onto loopback.
      const sentinel = "skip_thought_signature_validator";
      const text = await event.request.clone().text();
      if (!text.includes(sentinel)) return;
      const body = JSON.parse(text);
      let changed = false;
      for (const content of body.contents ?? []) {
        for (const part of content.parts ?? []) {
          if (part.functionCall && part.thoughtSignature === sentinel) {
            part.thoughtSignature = Buffer.from(sentinel).toString("base64");
            changed = true;
          }
        }
      }
      if (!changed) return;
      const requestHeaders = new Headers(event.request.headers);
      requestHeaders.delete("content-length");
      event.request = new Request(event.request, {
        headers: requestHeaders,
        body: JSON.stringify(body),
      });
    }, { providerID: "llmplatform" });
    return async () => {
      await signatureHook.dispose();
      await registration.dispose();
    };
  },
};
