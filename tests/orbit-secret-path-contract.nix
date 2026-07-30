{ lib, pkgs }:

let
  orbitModules = [
    ../modules/services/orbit.nix
    ../modules/system-manager/orbit.nix
  ];

  secretPathType =
    orbitModule:
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        orbitModule
        { _module.check = false; }
      ];
    }).options.local.orbit.enrollSecretPath.type;

  secretPathTypes = map secretPathType orbitModules;

  acceptsSafeValues = type: type.check null && type.check "/run/secrets/fleet_enroll_secret";

  rejectsUnsafeValues =
    type:
    !(type.check "run/secrets/fleet_enroll_secret")
    && !(type.check "/nix/store/00000000000000000000000000000000-example-orbit-secret")
    && !(type.check ../TODO.md);
in
lib.all (type: acceptsSafeValues type && rejectsUnsafeValues type) secretPathTypes
