# Example module demonstrating the local.* pattern
#
# This module:
# 1. Defines options under local.hello.*
# 2. Only activates when local.hello.enable = true
# 3. Creates a simple script as an example
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.hello;
in
{
  # ============================================================================
  # Options
  # ============================================================================
  options.local.hello = {
    enable = lib.mkEnableOption "hello greeting module";

    greeting = lib.mkOption {
      type = lib.types.str;
      default = "Hello, NixOS!";
      description = "The greeting message to display";
    };
  };

  # ============================================================================
  # Configuration (only applied when enabled)
  # ============================================================================
  config = lib.mkIf cfg.enable {
    # Create a script that prints the greeting
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "hello-nixos" ''
        echo "${cfg.greeting}"
      '')
    ];

    # Example: could also enable services, create files, etc.
    # services.something.enable = true;
  };
}
