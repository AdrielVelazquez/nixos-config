{ runCommand, scowl }:
runCommand "pi-ghost-wordlist" { } ''
  mkdir -p "$out/share/dict"
  cp ${scowl}/share/dict/wamerican.35 "$out/share/dict/wamerican.35"
  echo 'b31d847c962c964791909717a0b85ed977a6cd12b468687564291efc5b796e7a  '"$out/share/dict/wamerican.35" | sha256sum --check --strict
''
