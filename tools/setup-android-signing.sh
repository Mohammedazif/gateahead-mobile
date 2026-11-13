#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/.."
case "${1:-}" in
  ""|--local-only) ;;
  *) echo "Usage: bash tools/setup-android-signing.sh [--local-only]" >&2; exit 1 ;;
esac

signing_dir="$PWD/.signing"
keystore="$signing_dir/gateahead-android.p12"
password="$signing_dir/password.txt"
mkdir -p "$signing_dir"

if [[ ! -f "$keystore" ]]; then
  # Generate in a temporary directory so interrupted setup never leaves a partial key.
  work_dir=$(mktemp -d "$signing_dir/generate.XXXXXX")
  trap 'rm -rf "$work_dir"' EXIT
  openssl rand -base64 36 > "$work_dir/password.txt"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 10000 \
    -subj '/CN=GateAhead Android/O=GateAhead/C=IN' \
    -passout "file:$work_dir/password.txt" \
    -keyout "$work_dir/private.pem" -out "$work_dir/certificate.pem" 2>/dev/null
  openssl pkcs12 -export -name gateahead \
    -inkey "$work_dir/private.pem" -in "$work_dir/certificate.pem" \
    -passin "file:$work_dir/password.txt" -passout fd:3 \
    -out "$work_dir/gateahead-android.p12" 3< "$work_dir/password.txt"
  mv "$work_dir/password.txt" "$password"
  mv "$work_dir/gateahead-android.p12" "$keystore"
fi

if [[ ! -s "$password" ]]; then
  echo "Missing .signing/password.txt; restore it from your signing backup." >&2
  exit 1
fi
openssl pkcs12 -in "$keystore" -passin "file:$password" -noout
echo "Android signing key ready in .signing/. Back up this folder for future app updates."

if [[ "${1:-}" == --local-only ]]; then
  exit 0
fi

# gh infers this mobile repository from its Git remote. Secret values stay off stdout.
base64 < "$keystore" | gh secret set GATEAHEAD_ANDROID_KEYSTORE_BASE64
tr -d '\r\n' < "$password" | gh secret set GATEAHEAD_ANDROID_KEYSTORE_PASSWORD
echo "Android signing secrets uploaded to this repository."
