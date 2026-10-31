#!/usr/bin/env bash
set -euo pipefail

base=$1
certificate=$2
destination=$3
openssl x509 -in "$certificate" -noout
umask 077
temporary=$(mktemp "${destination}.XXXXXX")
trap 'rm -f "$temporary"' EXIT
{
  cat "$base"
  printf '\n'
  cat "$certificate"
  printf '\n'
} > "$temporary"
chmod 0644 "$temporary"
mv -f "$temporary" "$destination"
trap - EXIT
