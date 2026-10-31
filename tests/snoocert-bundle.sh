#!/usr/bin/env bash
set -euo pipefail

root=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

openssl req -x509 -newkey rsa:2048 -nodes -keyout base.key -out base.crt -days 1 -subj /CN=base >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout work.key -out work.crt -days 1 -subj /CN=work >/dev/null 2>&1
bash "$root/modules/system/snoocert-bundle.sh" base.crt work.crt bundle.crt
[ "$(grep -c 'BEGIN CERTIFICATE' bundle.crt)" -eq 2 ]
openssl verify -CAfile bundle.crt work.crt
cp bundle.crt previous.crt

printf 'invalid certificate\n' > invalid.crt
if bash "$root/modules/system/snoocert-bundle.sh" base.crt invalid.crt bundle.crt 2>/dev/null; then
  echo 'Invalid corporate certificate unexpectedly accepted' >&2
  exit 1
fi
cmp previous.crt bundle.crt
if bash "$root/modules/system/snoocert-bundle.sh" base.crt missing.crt bundle.crt 2>/dev/null; then
  echo 'Missing corporate certificate unexpectedly accepted' >&2
  exit 1
fi
cmp previous.crt bundle.crt

openssl req -x509 -newkey rsa:2048 -nodes -keyout rotated.key -out rotated.crt -days 1 -subj /CN=rotated >/dev/null 2>&1
bash "$root/modules/system/snoocert-bundle.sh" base.crt rotated.crt bundle.crt
[ "$(grep -c 'BEGIN CERTIFICATE' bundle.crt)" -eq 2 ]
openssl verify -CAfile bundle.crt rotated.crt
if cmp -s previous.crt bundle.crt; then
  echo 'Certificate rotation did not replace the bundle' >&2
  exit 1
fi
[ "$(stat -c %a bundle.crt)" = 644 ]

database="$work/nssdb"
bash "$root/modules/home-manager/snoocert-import.sh" work.crt "$database"
certutil -L -d "sql:$database" -n snoodev-ca -a > trusted.crt
[ "$(openssl x509 -in trusted.crt -noout -subject)" = 'subject=CN=work' ]
bash "$root/modules/home-manager/snoocert-import.sh" work.crt "$database"
bash "$root/modules/home-manager/snoocert-import.sh" rotated.crt "$database"
certutil -L -d "sql:$database" -n snoodev-ca -a > trusted.crt
[ "$(openssl x509 -in trusted.crt -noout -subject)" = 'subject=CN=rotated' ]
if bash "$root/modules/home-manager/snoocert-import.sh" invalid.crt "$database" 2>/dev/null; then
  echo 'Invalid NSS certificate unexpectedly accepted' >&2
  exit 1
fi
certutil -L -d "sql:$database" -n snoodev-ca -a > trusted.crt
[ "$(openssl x509 -in trusted.crt -noout -subject)" = 'subject=CN=rotated' ]
