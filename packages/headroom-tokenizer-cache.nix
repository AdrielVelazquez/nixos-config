{ pkgs }:
let
  vocabularies = {
    cl100k_base = "223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7";
    o200k_base = "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d";
  };
  entry =
    name: sha256:
    let
      url = "https://openaipublic.blob.core.windows.net/encodings/${name}.tiktoken";
      file = pkgs.fetchurl { inherit url sha256; };
    in
    ''ln -s ${file} "$out/${builtins.hashString "sha1" url}"'';
in
pkgs.runCommand "headroom-tokenizer-cache" { } ''
  mkdir -p "$out"
  ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList entry vocabularies)}
''
