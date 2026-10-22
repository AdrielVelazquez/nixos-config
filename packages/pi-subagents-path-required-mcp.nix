# pi-subagents 0.80.0 loads mandatory child extensions, but its foreground guard
# still rejects their MCP registrations as though every child were extension-free.
# Exempt only exact canonical registering files present in the required snapshot.
# Optional/ambient registrations remain rejected. TODO.md records removal gates.
''
  substituteInPlace "$out/node_modules/pi-subagents/src/runs/shared/child-launch.js" \
    --replace-fail \
      'const servers = extensionOnlyMcpServers(toolPlan.effectiveMcpSelections, input.runtimeSnapshotHost, input.cwd, input.projectTrusted !== false);' \
      'const requiredPaths = new Set(toolPlan.requiredExtensions.map(extension => extension.path));
          const requiredServers = new Set((input.runtimeSnapshotHost.getMcpServers?.() ?? []).filter(server => {
              try { return requiredPaths.has(fs.realpathSync(server.extensionPath)); }
              catch { return false; }
          }).map(server => server.name));
          const servers = extensionOnlyMcpServers(toolPlan.effectiveMcpSelections, input.runtimeSnapshotHost, input.cwd, input.projectTrusted !== false)
              .filter(server => !requiredServers.has(server));'
''
