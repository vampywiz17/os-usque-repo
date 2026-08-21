#!/bin/sh
set -eu
[ "$#" -eq 2 ] || exit 64
key="$1"; public_key="$2"
[ -f "$key" ] && [ -f "$public_key" ] || exit 66
IFS= read -r sum
[ -n "$sum" ] || exit 65
printf '%s\n' SIGNATURE
printf '%s' "$sum" | openssl dgst -sign "$key" -sha256 -binary
printf '\n%s\n' CERT
cat "$public_key"
printf '%s\n' END
