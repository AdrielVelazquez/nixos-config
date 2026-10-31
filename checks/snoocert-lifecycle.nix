{ pkgs }:
let
  certificates =
    pkgs.runCommand "snoocert-lifecycle-certificates"
      {
        nativeBuildInputs = [ pkgs.openssl ];
      }
      ''
        mkdir "$out"
        for name in first second; do
          openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "$TMPDIR/$name.key" -out "$out/$name.pem" \
            -days 1 -subj "/CN=$name" >/dev/null 2>&1
        done
      '';
in
pkgs.testers.runNixOSTest {
  name = "snoocert-lifecycle";

  nodes.machine = { lib, ... }: {
    imports = [ ../modules/system/snoocert.nix ];

    options.sops.secrets = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              default = "/run/snoocert-test.pem";
            };
            restartUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
        }
      );
    };

    config = {
      local.snoocert.enable = true;
      environment.systemPackages = [ pkgs.openssl ];

      # Substitute only secret delivery; exercise the real trust service and systemd lifecycle.
      systemd.services.sops-install-secrets = {
        wantedBy = [ "sysinit.target" ];
        before = [ "sysinit.target" ];
        after = [ "local-fs.target" ];
        unitConfig.DefaultDependencies = false;
        script = ''
          cp ${certificates}/first.pem /run/snoocert-test.pem
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("snoocert-trust.service")
    machine.succeed("cp /run/snoocert/ca-bundle.crt /tmp/known-good.crt")

    with subtest("failed restart preserves the last working system CA bundle"):
        machine.succeed("printf 'invalid certificate\\n' > /run/snoocert-test.pem")
        machine.fail("systemctl restart snoocert-trust.service")
        machine.succeed("systemctl is-failed --quiet snoocert-trust.service")
        machine.succeed("cmp /tmp/known-good.crt /run/snoocert/ca-bundle.crt")
        for bundle in [
            "/etc/ssl/certs/ca-certificates.crt",
            "/etc/ssl/certs/ca-bundle.crt",
            "/etc/pki/tls/certs/ca-bundle.crt",
        ]:
            machine.succeed(f"test -r {bundle}")
        machine.succeed("openssl verify -no_check_time -CAfile /etc/ssl/certs/ca-certificates.crt ${certificates}/first.pem")

    with subtest("a valid replacement recovers the failed service"):
        machine.succeed("cp ${certificates}/second.pem /run/snoocert-test.pem")
        machine.succeed("systemctl reset-failed snoocert-trust.service")
        machine.succeed("systemctl start snoocert-trust.service")
        machine.wait_for_unit("snoocert-trust.service")
        machine.fail("cmp /tmp/known-good.crt /run/snoocert/ca-bundle.crt")
        machine.succeed("openssl verify -no_check_time -CAfile /etc/ssl/certs/ca-certificates.crt ${certificates}/second.pem")
        machine.succeed("cp /run/snoocert/ca-bundle.crt /tmp/recovered.crt")

    with subtest("stopping the service does not break system certificate paths"):
        machine.succeed("systemctl stop snoocert-trust.service")
        machine.succeed("cmp /tmp/recovered.crt /etc/ssl/certs/ca-certificates.crt")
  '';
}
