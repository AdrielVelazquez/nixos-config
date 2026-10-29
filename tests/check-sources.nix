{
  lib,
  pkgs,
  sourcesForRoot,
}:
let
  fixtures = ./fixtures/check-sources;
  sources = variant: sourcesForRoot (fixtures + "/${variant}");
  check =
    variant:
    (import ../checks/pi-web-search.nix {
      inherit pkgs;
      checkSources = sources variant;
    }).pi-web-search.drvPath;
  nixSource = variant: toString (sources variant).nix-format;
in
assert lib.assertMsg (
  check "base" == check "unrelated"
) "an unrelated README edit must reuse the actual web-search check derivation";
assert lib.assertMsg (
  check "base" != check "code-change"
) "a tested extension edit must invalidate the actual web-search check derivation";
assert lib.assertMsg (
  check "base" != check "test-change"
) "a test edit must invalidate the actual web-search check derivation";
assert lib.assertMsg (
  nixSource "base" == nixSource "unrelated"
) "Nix formatting must ignore unrelated documentation edits";
assert lib.assertMsg (
  nixSource "base" != nixSource "new-nix"
) "Nix formatting must include newly added Nix files";
assert lib.assertMsg (
  builtins.pathExists ((sources "base").pi-web-search + "/tests/pi/search-cooldown.test.mjs")
  && builtins.pathExists (
    (sources "base").pi-web-search + "/dotfiles/pi/extensions/search-cooldown-core.ts"
  )
) "the scoped source must retain the test and its relative extension import";
true
