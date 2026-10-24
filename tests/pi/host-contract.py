#!/usr/bin/env python3
"""Final host selection: real flake outputs, never provisional overrides."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
expression = r'''
let f = builtins.getFlake ROOT;
  framework = f.homeConfigurations.cachyos-framework13.config;
  razer = f.nixosConfigurations.razer14.config.home-manager.users.adriel;
  names = home: map (p: p.pname or p.name or "") home.home.packages;
in {
  pi = framework.local.pi.enable && framework.local.pi.llmPlatform.enable && framework.local.pi.routing.enable && framework.local.pi.workflow.enable && framework.local.pi.openspec.enable && framework.local.headroom.pi.enable;
  frameworks = names framework;
  files = map (file: file.target) (builtins.attrValues framework.home.file);
  razerPiOff = !razer.local.pi.enable && !razer.local.pi.llmPlatform.enable && !razer.local.headroom.pi.enable && !razer.local.tuios.integrations.pi.enable;
  razerOpencode = razer.programs.opencode.enable && razer.local.tuios.integrations.opencode.enable;
  razerPackages = names razer;
  frameworkOpencodeOff = !framework.programs.opencode.enable && !framework.local.openspec.enable && !framework.local.tuios.integrations.opencode.enable;
  provider = framework.programs.pi-coding-agent.settings.defaultProvider or null;
  model = framework.programs.pi-coding-agent.settings.defaultModel or null;
  thinking = framework.programs.pi-coding-agent.settings.defaultThinkingLevel or null;
  alias = framework.programs.zsh.shellAliases.oc or null;
  razerAlias = razer.programs.zsh.shellAliases.oc or null;
  routes = framework.local.pi.modelRoles.taskAgents;
}
'''.replace("ROOT", json.dumps(str(root)))
result = subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expression], text=True, capture_output=True)
assert result.returncode == 0, result.stderr
data = json.loads(result.stdout)
assert data["pi"] and data["frameworkOpencodeOff"] and data["razerPiOff"] and data["razerOpencode"], data
assert data["frameworks"].count("pi-coding-agent") == 1 and "opencode" not in data["frameworks"] and data["frameworks"].count("llmp") == 1, data
assert "pi-coding-agent" not in data["razerPackages"] and "llmp" not in data["razerPackages"], data
assert not any(path.startswith(".config/opencode/") or path == ".npmrc" for path in data["files"]), data["files"]
assert (data["provider"], data["model"], data["thinking"]) == ("roles", "auto", "high"), data
assert data["alias"] == "pi" and data["razerAlias"] == "headroom wrap opencode", data
assert data["routes"]["plan"] == "@plan", data
print("PASS: exact Framework Pi cutover/defaults, no old managed OpenCode artifacts, one CLI, unchanged Razer harness and aliases")
