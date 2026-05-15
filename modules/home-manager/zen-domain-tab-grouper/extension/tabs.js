(function (globalScope) {
  const TAB_GROUP_ID_NONE = -1;

  function unique(values) {
    return Array.from(new Set(values));
  }

  function closeMenuTitle(groupName) {
    return groupName ? `Close "${groupName}" group` : "Close domain group";
  }

  function closeTargetTabIds(clickedTab, tabs, groupNameFromUrl) {
    if (!clickedTab || clickedTab.pinned) {
      return [];
    }

    const clickedGroupId = clickedTab.groupId ?? TAB_GROUP_ID_NONE;
    if (clickedGroupId !== TAB_GROUP_ID_NONE) {
      return tabs
        .filter((tab) => !tab.pinned && tab.groupId === clickedGroupId)
        .map((tab) => tab.id)
        .filter((tabId) => tabId != null);
    }

    const clickedGroupName = groupNameFromUrl(clickedTab.url);
    if (!clickedGroupName) {
      return [];
    }

    return tabs
      .filter((tab) => !tab.pinned && groupNameFromUrl(tab.url) === clickedGroupName)
      .map((tab) => tab.id)
      .filter((tabId) => tabId != null);
  }

  function groupingPlans(tabs, existingGroups, groupNameFromUrl, minTabsPerGroup) {
    const tabsByGroupName = new Map();

    for (const tab of tabs) {
      if (tab.pinned || !tab.url || tab.id == null) {
        continue;
      }

      const groupName = groupNameFromUrl(tab.url);
      if (!groupName) {
        continue;
      }

      const groupedTabs = tabsByGroupName.get(groupName) || [];
      groupedTabs.push(tab);
      tabsByGroupName.set(groupName, groupedTabs);
    }

    const plans = [];

    for (const [groupName, groupedTabs] of tabsByGroupName) {
      const existingGroupId = existingGroups.get(groupName) ?? null;
      const tabIds =
        existingGroupId == null
          ? groupedTabs.map((tab) => tab.id)
          : groupedTabs
              .filter((tab) => tab.groupId !== existingGroupId)
              .map((tab) => tab.id);

      const targetTabIds = unique(tabIds).filter((tabId) => tabId != null);
      if (groupedTabs.length < minTabsPerGroup || targetTabIds.length === 0) {
        continue;
      }

      plans.push({
        existingGroupId,
        groupName,
        tabIds: targetTabIds,
      });
    }

    return plans;
  }

  function regroupDelays(reason) {
    if (reason === "updated") {
      return [250, 1000, 2500];
    }

    if (reason === "created") {
      return [250, 1000];
    }

    return [250];
  }

  globalScope.ZenDomainTabGrouperTabs = {
    TAB_GROUP_ID_NONE,
    closeMenuTitle,
    closeTargetTabIds,
    groupingPlans,
    regroupDelays,
  };
})(globalThis);
