#!/usr/bin/env python3
"""Evaluate real Home Manager fixture outputs, without activating a host."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
expression = r'''
let
  f = builtins.getFlake ROOT;
  base = f.homeConfigurations.cachyos-framework13;
  enabled = (base.extendModules { modules = [{
    local.pi.enable = f.inputs.nixpkgs.lib.mkForce true;
    local.pi.llmPlatform.enable = f.inputs.nixpkgs.lib.mkForce false;
    local.pi.routing.enable = f.inputs.nixpkgs.lib.mkForce false;
    local.headroom.pi.enable = f.inputs.nixpkgs.lib.mkForce false;
    local.pi.workflow.enable = true;
    local.pi.openspec.enable = true;
  }]; }).config;
in {
  disabled = !f.nixosConfigurations.razer14.config.home-manager.users.adriel.local.pi.enable;
  native = enabled.programs.pi-coding-agent.enable;
  providerAbsent = !(enabled.programs.pi-coding-agent.settings ? defaultProvider);
  packageCount = builtins.length (builtins.filter (p: (p.pname or "") == "pi-coding-agent") enabled.home.packages);
  mcpFile = toString enabled.home.file."/home/adriel/.pi/agent/mcp.json".source;
  settings = enabled.programs.pi-coding-agent.settings;
  context = enabled.programs.pi-coding-agent.context;
}
'''.replace("ROOT", json.dumps(str(root)))
result = subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expression], text=True, capture_output=True)
assert result.returncode == 0, result.stderr
config = json.loads(result.stdout)
assert config["disabled"] and config["native"] and config["providerAbsent"], config
assert config["packageCount"] == 1, config["packageCount"]
assert len(config["settings"]["extensions"]) == 2, config["settings"]["extensions"]
assert len(config["settings"]["skills"]) == 3, config["settings"]["skills"]
assert not any("vault" in value for value in config["settings"]["skills"])
assert "Use Superpowers" in config["context"] and "question" in config["context"]
print("PASS: opt-in base Pi, one package, separate workflow/OpenSpec resources, no corporate defaults")
if len(sys.argv) > 1:
    Path(sys.argv[1]).write_text(json.dumps(config))
