// Regression: advertising first-party LLMP scopes must not poison ordinary DCR sign-in.
import assert from "node:assert/strict"
import { resolve } from "node:path"
import { pathToFileURL } from "node:url"
import test from "node:test"

const pluginRoot = resolve(process.argv[2])
const { createToolsOAuth, DEFAULT_TOOLS_URL } = await import(
  pathToFileURL(`${pluginRoot}/src/tools-oauth.mjs`).href
)
const issuer = "https://llm-platform.snooguts.net/api/oauth"
const metadata = {
  resource: DEFAULT_TOOLS_URL,
  authorization_servers: [issuer],
  scopes_supported: [
    "openid", "offline_access", "tool:llmp:*", "tool:github:*",
    "tool:llmp:list_skills", "tool:llmp-other:read", "tool:github:*",
  ],
}
const ordinaryScope = "openid offline_access tool:github:* tool:llmp-other:read"

async function fixture(t, { cached, discovery = metadata } = {}) {
  let response = discovery
  const warnings = []
  const storage = new Map(cached ? [["cached", structuredClone(cached)]] : [])
  const context = {
    options: {},
    storage: {
      async get() { return storage.get("cached") },
      async set(_key, value) { storage.set("cached", value) },
    },
    mcp: { async reload() {} },
  }
  const oauth = await createToolsOAuth(context, DEFAULT_TOOLS_URL, {
    async fetch(url) {
      assert.equal(url, "https://llm-platform.snooguts.net/.well-known/oauth-protected-resource/api/mcp")
      if (response instanceof Error) throw response
      return new Response(JSON.stringify(response))
    },
    warn(message) { warnings.push(message) },
  })
  t.after(() => oauth.dispose())
  return {
    oauth, warnings,
    discover(value) { response = value },
    config() {
      const config = { type: "remote", url: DEFAULT_TOOLS_URL }
      oauth.apply(config)
      return config
    },
  }
}

test("fresh discovery excludes only restricted LLMP scopes and deduplicates ordinary scopes", async (t) => {
  const { config } = await fixture(t)
  assert.equal(config().oauth.scope, ordinaryScope)
})

test("cached metadata excludes restricted scopes even while discovery is offline", async (t) => {
  const { config } = await fixture(t, { cached: metadata, discovery: new Error("offline") })
  assert.equal(config().oauth.scope, ordinaryScope)
})

test("refresh cannot reintroduce restricted scopes", async (t) => {
  const subject = await fixture(t, {
    discovery: { ...metadata, scopes_supported: ["openid", "tool:github:read"] },
  })
  assert.equal(subject.config().oauth.scope, "openid tool:github:read")
  subject.discover(metadata)
  await subject.oauth.refresh()
  assert.equal(subject.config().oauth.scope, ordinaryScope)
})

test("explicit OAuth scopes and pre-registered client settings remain operator-owned", async (t) => {
  const { oauth } = await fixture(t)
  const config = {
    type: "remote", url: DEFAULT_TOOLS_URL,
    oauth: { scope: "openid tool:llmp:list_skills", client_id: "approved-fixture", callback_port: 19876 },
  }
  assert.equal(oauth.apply(config), false)
  assert.equal(config.oauth.scope, "openid tool:llmp:list_skills")
  assert.equal(config.oauth.client_id, "approved-fixture")
  assert.equal(config.oauth.callback_port, 19876)
})

test("disabled OAuth remains disabled", async (t) => {
  const { oauth } = await fixture(t)
  const config = { type: "remote", url: DEFAULT_TOOLS_URL, oauth: false }
  assert.equal(oauth.apply(config), false)
  assert.equal(config.oauth, false)
})

for (const [name, invalid] of [
  ["untrusted issuer", { ...metadata, authorization_servers: ["https://untrusted.invalid"] }],
  ["wrong resource", { ...metadata, resource: "https://untrusted.invalid/api/mcp" }],
  ["malformed restricted scope", { ...metadata, scopes_supported: ["openid", "tool:llmp:bad scope"] }],
  ["restricted-only metadata", { ...metadata, scopes_supported: ["tool:llmp:*", "tool:llmp:list_skills"] }],
]) {
  test(`${name} cannot supply default scopes from discovery or cache`, async (t) => {
    const subject = await fixture(t, { cached: invalid, discovery: invalid })
    assert.equal(subject.config().oauth.scope, undefined)
    assert.equal(subject.warnings.length, 1)
  })
}

test("local package retains the plugin identity used for existing storage", async () => {
  const { default: plugin } = await import(pathToFileURL(`${pluginRoot}/index.mjs`).href)
  assert.equal(plugin.id, "@reddit/opencode-llm-platform-v2")
})
