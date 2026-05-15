import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./domain.js", import.meta.url), "utf8");
const context = vm.createContext({ URL, globalThis: { URL } });
context.globalThis.globalThis = context.globalThis;
vm.runInContext(source, context);

const { groupNameFromUrl } = context.globalThis.ZenDomainTabGrouperDomain;

assert.equal(groupNameFromUrl("https://github.com/reddit/repo"), "github.com");
assert.equal(groupNameFromUrl("https://mail.google.com/mail/u/0/"), "google.com");
assert.equal(groupNameFromUrl("https://www.reddit.com/r/nixos"), "reddit.com");
assert.equal(groupNameFromUrl("https://docs.python.org/3/"), "python.org");
assert.equal(groupNameFromUrl("https://bbc.co.uk/news"), "bbc.co.uk");
assert.equal(groupNameFromUrl("http://localhost:3000/"), "localhost");
assert.equal(groupNameFromUrl("http://127.0.0.1:3000/"), "localhost");
assert.equal(groupNameFromUrl("http://127.12.34.56:3000/"), "localhost");
assert.equal(groupNameFromUrl("http://0.0.0.0:3000/"), "localhost");
assert.equal(groupNameFromUrl("http://[::1]:3000/"), "localhost");
assert.equal(groupNameFromUrl("http://app.localhost:3000/"), "localhost");
assert.equal(groupNameFromUrl("http://localhost.localdomain:3000/"), "localhost");
assert.equal(groupNameFromUrl("about:newtab"), null);
assert.equal(groupNameFromUrl("zen:newtab"), null);
assert.equal(groupNameFromUrl("moz-extension://example/sidebar.html"), null);
