#!/usr/bin/env python3
"""Check corporate Pi integration is opt-in and absent from Razer."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
provider = Path(sys.argv[1]).resolve()
expr = r'''
let
  f = builtins.getFlake ROOT;
  base = f.homeConfigurations.cachyos-framework13;
  lib = f.inputs.nixpkgs.lib;
  off = { local.pi.llmPlatform.enable = lib.mkForce false; local.pi.routing.enable = lib.mkForce false; local.headroom.pi.enable = lib.mkForce false; };
  plain = (base.extendModules { modules = [off { local.pi.enable = true; }]; }).config;
  work = (base.extendModules { modules = [{ local.pi = {
    enable = true;
    llmPlatform = { enable = true; package = lib.mkForce PROVIDER; cli.enable = true; };
  }; local.pi.routing.enable = lib.mkForce false; local.headroom.pi.enable = lib.mkForce false; }]; }).config;
  razer = f.nixosConfigurations.razer14.config.home-manager.users.adriel;
in {
  baseOff = !plain.local.pi.llmPlatform.enable;
  baseRuntimeAbsent = plain.local.pi.llmPlatform.runtimePackage == null;
  workRuntimePresent = work.local.pi.llmPlatform.runtimePackage != null;
  runtimePath = toString work.local.pi.llmPlatform.runtimePackage;
  plainProviderAbsent = !(plain.programs.pi-coding-agent.settings ? defaultProvider);
  provider = work.programs.pi-coding-agent.settings.defaultProvider;
  packageCount = builtins.length work.programs.pi-coding-agent.settings.packages;
  required = map (entry: entry.id) work.local.pi.requiredChildExtensions;
  llmp = builtins.length (f.inputs.nixpkgs.lib.unique (builtins.filter (p: (p.pname or "") == "llmp") work.home.packages));
  razerOff = !razer.local.pi.enable && !razer.local.pi.llmPlatform.enable;
  razerOpencode = razer.programs.opencode.enable;
}
'''.replace("ROOT", json.dumps(str(root))).replace("PROVIDER", f"(builtins.toPath {json.dumps(str(provider))})")
result = subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expr], text=True, capture_output=True)
assert result.returncode == 0, result.stderr
data = json.loads(result.stdout)
assert data["baseOff"] and data["plainProviderAbsent"] and data["razerOff"] and data["razerOpencode"], data
assert data["baseRuntimeAbsent"] and data["workRuntimePresent"], data
assert data["provider"] == "llm-platform" and data["packageCount"] == 1 and data["llmp"] == 1, data
assert data["required"] == ["reddit-provider"], data
print("PASS: explicit work provider and CLI, required child source, no corporate defaults in base or Razer")
if len(sys.argv) > 2:
    Path(sys.argv[2]).write_text(json.dumps(data))
