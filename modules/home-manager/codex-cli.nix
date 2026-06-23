{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.codex-cli;
  githubTokenSecretName = "codex_github_token";
  githubTokenEnvVar = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN";
  githubCopilotMcpUrl = "https://api.githubcopilot.com/mcp/";

  codexWithGithubToken = pkgs.writeShellScriptBin "codex" ''
    if [ -z "''${${githubTokenEnvVar}:-}" ] && [ -r "${
      config.sops.secrets.${githubTokenSecretName}.path
    }" ]; then
      export ${githubTokenEnvVar}="$(${pkgs.coreutils}/bin/cat "${
        config.sops.secrets.${githubTokenSecretName}.path
      }")"
    fi

    exec ${pkgs.codex}/bin/codex "$@"
  '';
in
{
  options.local.codex-cli = {
    enable = lib.mkEnableOption "Codex CLI";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${githubTokenSecretName} = { };

    home.packages = [ (lib.hiPrio codexWithGithubToken) ];

    home.activation.configureCodexGithubCopilotMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_dir="${config.home.homeDirectory}/.codex"
      config_file="$config_dir/config.toml"
      section="[mcp_servers.official_github]"
      url_line='url = "${githubCopilotMcpUrl}"'
      token_line='bearer_token_env_var = "${githubTokenEnvVar}"'

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would configure GitHub Copilot MCP in $config_file"
      else
        ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
        if [ ! -e "$config_file" ]; then
          ${pkgs.coreutils}/bin/install -m 600 /dev/null "$config_file"
        fi

        tmp="$config_file.tmp.$$"
        ${pkgs.gawk}/bin/awk -v section="$section" -v url="$url_line" -v token="$token_line" '
          function finish_section() {
            if (in_section) {
              if (!seen_url) print url
              if (!seen_token) print token
            }
            in_section = 0
            seen_url = 0
            seen_token = 0
          }

          $0 == section {
            finish_section()
            print
            in_section = 1
            seen_section = 1
            next
          }

          /^[[:space:]]*#?[[:space:]]*\[/ {
            finish_section()
            print
            next
          }

          in_section && /^[[:space:]]*url[[:space:]]*=/ {
            if (!seen_url) print url
            seen_url = 1
            next
          }

          in_section && /^[[:space:]]*bearer_token_env_var[[:space:]]*=/ {
            if (!seen_token) print token
            seen_token = 1
            next
          }

          { print }

          END {
            finish_section()
            if (!seen_section) {
              print ""
              print section
              print url
              print token
            }
          }
        ' "$config_file" > "$tmp"

        if ! ${pkgs.diffutils}/bin/cmp -s "$tmp" "$config_file"; then
          ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$config_file"
        fi
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    '';

    home.activation.configureCodexHeadroomHttp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_file="${config.home.homeDirectory}/.codex/config.toml"
      section="[model_providers.headroom]"
      websocket_line='supports_websockets = false'

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would configure Headroom Codex HTTP fallback in $config_file"
      elif [ -e "$config_file" ]; then
        tmp="$config_file.tmp.$$"
        ${pkgs.gawk}/bin/awk -v section="$section" -v websocket="$websocket_line" '
          function finish_section() {
            if (in_section && !seen_websocket) print websocket
            in_section = 0
            seen_websocket = 0
          }

          $0 == section {
            finish_section()
            print
            in_section = 1
            next
          }

          /^[[:space:]]*#?[[:space:]]*\[/ {
            finish_section()
            print
            next
          }

          in_section && /^[[:space:]]*supports_websockets[[:space:]]*=/ {
            if (!seen_websocket) print websocket
            seen_websocket = 1
            next
          }

          { print }

          END {
            finish_section()
          }
        ' "$config_file" > "$tmp"

        if ! ${pkgs.diffutils}/bin/cmp -s "$tmp" "$config_file"; then
          ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$config_file"
        fi
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    '';

    local.ai-cli-skills = {
      enable = true;
      targets.codex = true;
    };
  };
}
