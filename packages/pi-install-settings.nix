{ pkgs }:
pkgs.writeShellApplication {
  name = "pi-install-settings";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    # Install the Nix-generated Pi settings as a writable file: pi-install-settings MANAGED TARGET
    # Pi and its extensions persist choices into settings.json at runtime, which fails with EACCES
    # through a symlink into the read-only store. Every switch resets the file to the Nix
    # settings; a runtime-modified file is kept once as TARGET.replaced.
    managed=$1
    target=$2
    directory=$(dirname -- "$target")

    mkdir -p -- "$directory"
    if [ -f "$target" ] && [ ! -L "$target" ]; then
      if cmp -s -- "$managed" "$target"; then
        exit 0
      fi
      cp -f -- "$target" "$target.replaced"
      echo "pi: replaced runtime changes in $target; previous copy kept as $target.replaced" >&2
    fi
    temporary=$(mktemp -- "$directory/.settings.json.XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    install -m 0644 -- "$managed" "$temporary"
    # Renaming replaces a symlink itself and never writes through it into the store.
    mv -fT -- "$temporary" "$target"
  '';
}
