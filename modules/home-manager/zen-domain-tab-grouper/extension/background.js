(function () {
  const MIN_TABS_PER_GROUP = 2;
  const REGROUP_DELAY_MS = 250;
  const COLORS = [
    "blue",
    "green",
    "yellow",
    "red",
    "purple",
    "pink",
    "cyan",
    "orange",
    "grey",
  ];
  const CLOSE_GROUP_MENU_ID = "zen-domain-tab-grouper-close-group";

  const { groupNameFromUrl } = globalThis.ZenDomainTabGrouperDomain;
  const { closeMenuTitle, closeTargetTabIds, groupingPlans, regroupDelays } =
    globalThis.ZenDomainTabGrouperTabs;
  const scheduledWindows = new Map();

  function colorForGroupName(groupName) {
    let hash = 0;
    for (const character of groupName) {
      hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
    }
    return COLORS[hash % COLORS.length];
  }

  async function findExistingGroups(windowId) {
    const groups = await browser.tabGroups.query({ windowId });
    const byTitle = new Map();

    for (const group of groups) {
      if (group.title) {
        byTitle.set(group.title, group.id);
      }
    }

    return byTitle;
  }

  async function ensureGroup(groupName, tabIds, existingGroupId) {
    const groupId =
      existingGroupId == null
        ? await browser.tabs.group({ tabIds })
        : await browser.tabs.group({ tabIds, groupId: existingGroupId });

    await browser.tabGroups.update(groupId, {
      title: groupName,
      color: colorForGroupName(groupName),
    });

    return groupId;
  }

  async function regroupWindow(windowId) {
    if (windowId == null || windowId === browser.windows.WINDOW_ID_NONE) {
      return;
    }

    const tabs = await browser.tabs.query({ windowId });
    const existingGroups = await findExistingGroups(windowId);
    const plans = groupingPlans(tabs, existingGroups, groupNameFromUrl, MIN_TABS_PER_GROUP);

    if (plans.length > 0) {
      console.debug("[Zen Domain Tab Grouper] Applying regroup plans", plans);
    }

    for (const plan of plans) {
      const groupId = await ensureGroup(plan.groupName, plan.tabIds, plan.existingGroupId);
      existingGroups.set(plan.groupName, groupId);
    }
  }

  function scheduleRegroup(windowId, reason = "default") {
    if (windowId == null || windowId === browser.windows.WINDOW_ID_NONE) {
      return;
    }

    if (scheduledWindows.has(windowId)) {
      clearTimeout(scheduledWindows.get(windowId));
    }

    const timer = setTimeout(() => {
      scheduledWindows.delete(windowId);
      regroupWindow(windowId).catch((error) => {
        console.error(`[Zen Domain Tab Grouper] Failed to regroup tabs after ${reason}`, error);
      });
    }, REGROUP_DELAY_MS);

    scheduledWindows.set(windowId, timer);
  }

  function scheduleRegroupRetries(windowId, reason) {
    for (const delay of regroupDelays(reason)) {
      setTimeout(() => {
        regroupWindow(windowId).catch((error) => {
          console.error(`[Zen Domain Tab Grouper] Failed delayed regroup after ${reason}`, error);
        });
      }, delay);
    }
  }

  async function regroupAllWindows() {
    const windows = await browser.windows.getAll({ populate: false });
    for (const windowInfo of windows) {
      scheduleRegroup(windowInfo.id, "startup");
    }
  }

  async function closeGroupForTab(tab) {
    if (!tab || tab.windowId == null) {
      return;
    }

    const tabs = await browser.tabs.query({ windowId: tab.windowId });
    const tabIds = closeTargetTabIds(tab, tabs, groupNameFromUrl);
    if (tabIds.length > 0) {
      await browser.tabs.remove(tabIds);
    }
  }

  async function groupNameForTab(tab) {
    if (!tab || tab.pinned) {
      return null;
    }

    const groupId = tab.groupId ?? browser.tabGroups.TAB_GROUP_ID_NONE;
    if (groupId !== browser.tabGroups.TAB_GROUP_ID_NONE) {
      try {
        const group = await browser.tabGroups.get(groupId);
        if (group && group.title) {
          return group.title;
        }
      } catch (error) {
        console.debug("[Zen Domain Tab Grouper] Failed to read tab group title", error);
      }
    }

    return groupNameFromUrl(tab.url);
  }

  async function updateCloseGroupMenu(tab) {
    const groupName = await groupNameForTab(tab);
    await browser.contextMenus.update(CLOSE_GROUP_MENU_ID, {
      enabled: Boolean(groupName),
      title: closeMenuTitle(groupName),
    });

    if (browser.contextMenus.refresh) {
      await browser.contextMenus.refresh();
    }
  }

  async function createContextMenu() {
    await browser.contextMenus.removeAll();
    browser.contextMenus.create({
      id: CLOSE_GROUP_MENU_ID,
      title: closeMenuTitle(null),
      contexts: ["tab"],
    });
  }

  browser.runtime.onInstalled.addListener(() => {
    createContextMenu();
    regroupAllWindows();
  });
  browser.runtime.onStartup.addListener(regroupAllWindows);
  browser.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId === CLOSE_GROUP_MENU_ID) {
      closeGroupForTab(tab).catch((error) => {
        console.error("[Zen Domain Tab Grouper] Failed to close group", error);
      });
    }
  });
  if (browser.contextMenus.onShown) {
    browser.contextMenus.onShown.addListener((_info, tab) => {
      updateCloseGroupMenu(tab).catch((error) => {
        console.error("[Zen Domain Tab Grouper] Failed to update close group menu", error);
      });
    });
  }
  browser.tabs.onCreated.addListener((tab) => scheduleRegroupRetries(tab.windowId, "created"));
  browser.tabs.onRemoved.addListener((_tabId, removeInfo) => {
    if (!removeInfo.isWindowClosing) {
      scheduleRegroup(removeInfo.windowId);
    }
  });
  browser.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
    if (changeInfo.url || changeInfo.status === "complete") {
      scheduleRegroupRetries(tab.windowId, "updated");
    }
  });
  browser.tabs.onAttached.addListener((_tabId, attachInfo) => {
    scheduleRegroup(attachInfo.newWindowId);
  });
  browser.tabs.onMoved.addListener((_tabId, moveInfo) => {
    scheduleRegroup(moveInfo.windowId);
  });
  browser.windows.onFocusChanged.addListener(scheduleRegroup);

  regroupAllWindows().catch((error) => {
    console.error("[Zen Domain Tab Grouper] Failed initial regroup", error);
  });
  createContextMenu().catch((error) => {
    console.error("[Zen Domain Tab Grouper] Failed to create context menu", error);
  });
})();
