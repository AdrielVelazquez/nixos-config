export function withLlmPlatformProxy<T>(
  required: boolean,
  initialize: () => T,
  env: NodeJS.ProcessEnv = process.env,
): T {
  const urlKey = "LLM_PLATFORM_INFERENCE_PROXY_URL";
  const requiredKey = "LLM_PLATFORM_INFERENCE_PROXY_REQUIRED";
  const proxy = env[urlKey];
  if (required) {
    if (proxy === undefined || proxy !== env.HEADROOM_PROXY_URL || !/^http:\/\/127\.0\.0\.1:\d+$/.test(proxy)
      || env[requiredKey] !== "1") {
      throw new Error("Start Pi through the managed Headroom launcher; LLM Platform inference is disabled");
    }
    return initialize();
  }
  const previous = { [urlKey]: env[urlKey], [requiredKey]: env[requiredKey] };
  delete env[urlKey];
  delete env[requiredKey];
  try {
    // The provider snapshots its contract synchronously, before its first await.
    return initialize();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete env[key];
      else env[key] = value;
    }
  }
}
