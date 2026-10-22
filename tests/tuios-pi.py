#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
expression = r'''
let f = builtins.getFlake ROOT; base = f.homeConfigurations.cachyos-framework13;
  c = (base.extendModules { modules = [{ local.pi = { enable = true; agentDir = "/home/adriel/.pi-fixture/agent"; }; }]; }).config;
  razer = f.nixosConfigurations.razer14.config.home-manager.users.adriel;
in {
  baseOff = !(base.extendModules { modules = [{ local.pi.enable = f.inputs.nixpkgs.lib.mkForce false; }]; }).config.local.tuios.integrations.pi.enable;
  pi = c.local.tuios.integrations.pi.enable;
  source = toString c.home.file."/home/adriel/.pi-fixture/agent/extensions/tuios-agent-state.ts".source;
  outcomes = toString c.home.file."/home/adriel/.pi-fixture/agent/extensions/tuios-outcomes.ts".source;
  razerOff = !razer.local.tuios.integrations.pi.enable;
  razerOpencode = razer.local.tuios.integrations.opencode.enable;
  package = toString c.local.tuios.package;
}
'''.replace("ROOT", json.dumps(str(root)))
result = subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expression], text=True, capture_output=True)
assert result.returncode == 0, result.stderr
data = json.loads(result.stdout)
assert data["baseOff"] and data["pi"] and data["razerOff"] and data["razerOpencode"], data
assert data["source"].endswith("/tuios-agent-state.ts") and data["outcomes"].endswith("tuios-outcomes.ts"), data
if len(sys.argv) > 1:
    Path(sys.argv[1]).write_text(result.stdout)
print("PASS: Pi hook opt-in, custom native agentDir, and unchanged Razer OpenCode integration")
