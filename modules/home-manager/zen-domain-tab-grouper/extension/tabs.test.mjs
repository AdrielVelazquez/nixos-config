import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const domainSource = fs.readFileSync(new URL("./domain.js", import.meta.url), "utf8");
const tabsSource = fs.readFileSync(new URL("./tabs.js", import.meta.url), "utf8");
const context = vm.createContext({ URL, globalThis: { URL } });
context.globalThis.globalThis = context.globalThis;
vm.runInContext(domainSource, context);
vm.runInContext(tabsSource, context);

const { groupNameFromUrl } = context.globalThis.ZenDomainTabGrouperDomain;
const { closeMenuTitle, closeTargetTabIds, groupingPlans, regroupDelays } =
  context.globalThis.ZenDomainTabGrouperTabs;

function nativeArray(value) {
  return Array.from(value);
}

function nativeJson(value) {
  return JSON.parse(JSON.stringify(value));
}

assert.deepEqual(
  nativeArray(closeTargetTabIds(
    { id: 1, groupId: 42, pinned: false, url: "https://github.com/a" },
    [
      { id: 1, groupId: 42, pinned: false, url: "https://github.com/a" },
      { id: 2, groupId: 42, pinned: false, url: "https://github.com/b" },
      { id: 3, groupId: 42, pinned: true, url: "https://github.com/c" },
      { id: 4, groupId: 9, pinned: false, url: "https://reddit.com" },
    ],
    groupNameFromUrl,
  )),
  [1, 2],
);

assert.deepEqual(
  nativeArray(closeTargetTabIds(
    { id: 10, groupId: -1, pinned: false, url: "https://mail.google.com/mail" },
    [
      { id: 10, groupId: -1, pinned: false, url: "https://mail.google.com/mail" },
      { id: 11, groupId: -1, pinned: false, url: "https://docs.google.com/document" },
      { id: 12, groupId: -1, pinned: true, url: "https://drive.google.com/file" },
      { id: 13, groupId: -1, pinned: false, url: "about:newtab" },
      { id: 14, groupId: -1, pinned: false, url: "https://github.com" },
    ],
    groupNameFromUrl,
  )),
  [10, 11],
);

assert.deepEqual(
  nativeArray(closeTargetTabIds(
    { id: 20, groupId: -1, pinned: false, url: "about:newtab" },
    [{ id: 20, groupId: -1, pinned: false, url: "about:newtab" }],
    groupNameFromUrl,
  )),
  [],
);

assert.deepEqual(
  nativeJson(groupingPlans(
    [
      { id: 1, groupId: 7, pinned: false, url: "https://github.com/repo/a" },
      { id: 2, groupId: -1, pinned: false, url: "https://github.com/repo/b" },
      { id: 3, groupId: -1, pinned: false, url: "https://reddit.com/r/nixos" },
    ],
    new Map([["github.com", 7]]),
    groupNameFromUrl,
    2,
  )),
  [
    {
      existingGroupId: 7,
      groupName: "github.com",
      tabIds: [2],
    },
  ],
);

assert.deepEqual(nativeArray(regroupDelays("created")), [250, 1000]);
assert.deepEqual(nativeArray(regroupDelays("updated")), [250, 1000, 2500]);
assert.deepEqual(nativeArray(regroupDelays("startup")), [250]);

assert.equal(closeMenuTitle("github.com"), 'Close "github.com" group');
assert.equal(closeMenuTitle("localhost"), 'Close "localhost" group');
assert.equal(closeMenuTitle(null), "Close domain group");

assert.deepEqual(
  nativeJson(groupingPlans(
    [
      { id: 4, groupId: -1, pinned: false, url: "https://news.ycombinator.com/item" },
      { id: 5, groupId: -1, pinned: false, url: "https://news.ycombinator.com/news" },
    ],
    new Map(),
    groupNameFromUrl,
    2,
  )),
  [
    {
      existingGroupId: null,
      groupName: "ycombinator.com",
      tabIds: [4, 5],
    },
  ],
);
