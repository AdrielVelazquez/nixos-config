{
  lib,
  pkgs,
  python3,
  runCommand,
  scowl,
}:
let
  # The frequency list is data inside this exact package version; review the word ranking before bumping it.
  wordfreq = python3.pkgs.wordfreq;
  python = python3.withPackages (_: [ wordfreq ]);
  # Names of everything nixpkgs packages are tool vocabulary (kubectl, terraform, ripgrep) that no
  # English dictionary or web frequency list carries.
  packageNames = builtins.toFile "nixpkgs-attribute-names" (
    lib.concatStringsSep "\n" (builtins.attrNames pkgs)
  );
in
assert lib.assertMsg (wordfreq.version == "3.2.0")
  "pi-ghost-wordlist pins wordfreq 3.2.0; review the generated vocabulary before accepting ${wordfreq.version}";
runCommand "pi-ghost-wordlist" { nativeBuildInputs = [ python ]; } ''
  mkdir -p "$out/share/dict"
  echo 'b31d847c962c964791909717a0b85ed977a6cd12b468687564291efc5b796e7a  ${scowl}/share/dict/wamerican.35' | sha256sum --check --strict
  python3 -E - ${scowl}/share/dict/wamerican.35 ${packageNames} "$out/share/dict/ghost-vocabulary.tsv" <<'PY'
  import re
  import sys
  from collections import Counter
  from wordfreq import get_frequency_dict

  scowl, names, destination = sys.argv[1:]
  word = re.compile(r"(?:[^\W\d_]|')+")


  def usable(candidate, shortest):
      return shortest <= len(candidate) <= 40 and word.fullmatch(candidate) is not None


  # Web-scale frequency prior: probability of each word per token (sums to about 1).
  vocabulary = {w: f for w, f in get_frequency_dict("en", wordlist="large").items() if usable(w, 2)}
  # Dictionary words without any web frequency join with a zero weight.
  with open(scowl, encoding="latin-1") as handle:
      for line in handle:
          candidate = line.strip().lower()
          if usable(candidate, 2):
              vocabulary.setdefault(candidate, 0.0)
  # Tool names: how many package names use a token is a popularity proxy, so kubectl (dozens of
  # plugins) outranks kubecolor when typing "kubec". Always far below any real web frequency.
  packages = Counter()
  with open(names, encoding="utf-8") as handle:
      for line in handle:
          packages.update({part for part in re.split(r"[^A-Za-z]+", line.strip()) if part.islower() and usable(part, 3) and len(part) <= 24})
  for part, count in packages.items():
      if vocabulary.get(part, 0.0) == 0.0:
          vocabulary[part] = count * 2e-9
  with open(destination, "w", encoding="utf-8") as out:
      # Sorted once here so the extension never sorts a quarter of a million words at startup.
      for candidate in sorted(vocabulary):
          weight = vocabulary[candidate]
          out.write(f"{candidate}\t{weight:.3e}\n" if weight > 0 else f"{candidate}\n")
  PY
''
