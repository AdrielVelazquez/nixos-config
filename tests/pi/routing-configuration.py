#!/usr/bin/env python3
"""Materialize the real Nix-generated role contract for its upstream parser."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
expression = r'''
let
  f = builtins.getFlake ROOT;
  roles = {
    plan = { model = "llm-platform/claude-sonnet-5-5"; thinking = "xhigh"; };
    build = { model = "llm-platform/gpt-6.1-sol"; thinking = "high"; };
    scout = { model = "llm-platform/gpt-6.1-sol"; thinking = "low"; };
    explore = { model = "llm-platform/gpt-6-luna"; thinking = "low"; };
    title = { model = "llm-platform/gpt-6-luna"; thinking = "low"; };
  };
  c = (f.homeConfigurations.cachyos-framework13.extendModules { modules = [{
    local.pi = { enable = true; routing = { enable = true; agents = roles; };
      llmPlatform = { enable = true; package = f.inputs.pi-reddit-provider.outPath; }; };
    local.headroom.pi.enable = true;
  }]; }).config;
in {
  roles = builtins.mapAttrs (name: _: c.home.file."/home/adriel/.pi/agent/agents/${name}.md".text) roles;
  settings = c.programs.pi-coding-agent.settings;
}
'''.replace("ROOT", json.dumps(str(root)))
result = subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expression], capture_output=True, text=True)
assert result.returncode == 0, result.stderr
Path(sys.argv[1]).write_text(result.stdout)
