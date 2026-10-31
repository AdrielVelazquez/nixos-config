#!/usr/bin/env bash
set -euo pipefail

certificate=$1
database=$2
umask 077
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
openssl x509 -in "$certificate" -out "$temporary/candidate.pem"
mkdir -p "$database"

if certutil -L -d "sql:$database" -n snoodev-ca -a > "$temporary/previous.pem" 2>/dev/null; then
  openssl x509 -in "$temporary/candidate.pem" -outform DER -out "$temporary/candidate.der"
  openssl x509 -in "$temporary/previous.pem" -outform DER -out "$temporary/previous.der"
  if cmp -s "$temporary/candidate.der" "$temporary/previous.der"; then
    certutil -A -d "sql:$database" -n snoodev-ca -t TC -i "$temporary/candidate.pem"
    exit 0
  fi

  backup="snoodev-ca-${temporary##*/}"
  certutil --rename -d "sql:$database" -n snoodev-ca --new-n "$backup"
  if ! certutil -A -d "sql:$database" -n snoodev-ca -t TC -i "$temporary/candidate.pem"; then
    certutil --rename -d "sql:$database" -n "$backup" --new-n snoodev-ca
    exit 1
  fi
  certutil -D -d "sql:$database" -n "$backup"
else
  certutil -A -d "sql:$database" -n snoodev-ca -t TC -i "$temporary/candidate.pem"
fi
