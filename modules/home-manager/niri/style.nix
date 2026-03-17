{
  lib,
  ...
}:
{
  options.local.niri.style = {
    font.family = lib.mkOption {
      type = lib.types.str;
      default = "Maple Mono NF";
      description = "Primary UI font family for niri desktop components.";
    };

    palette = {
      background = lib.mkOption {
        type = lib.types.str;
        default = "#000000";
        description = "Base background color.";
      };
      foreground = lib.mkOption {
        type = lib.types.str;
        default = "#cdd6f4";
        description = "Primary foreground color.";
      };
      accent = lib.mkOption {
        type = lib.types.str;
        default = "#5a9cbf";
        description = "Primary accent color.";
      };
      accentAlt = lib.mkOption {
        type = lib.types.str;
        default = "#cba6f7";
        description = "Secondary accent color.";
      };
      muted = lib.mkOption {
        type = lib.types.str;
        default = "#6c7086";
        description = "Muted foreground color.";
      };
      inactive = lib.mkOption {
        type = lib.types.str;
        default = "#383838";
        description = "Inactive border and outline color.";
      };
      warning = lib.mkOption {
        type = lib.types.str;
        default = "#f9e2af";
        description = "Warning color.";
      };
      danger = lib.mkOption {
        type = lib.types.str;
        default = "#f38ba8";
        description = "Danger color.";
      };
      success = lib.mkOption {
        type = lib.types.str;
        default = "#c7ff7f";
        description = "Success color.";
      };
    };
  };
}
