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

pinned=""
if [[ "${1:-}" != --local-only ]]; then
  pinned=$(gh variable list --json name,value \
    --jq '.[] | select(.name == "GATEAHEAD_ANDROID_CERT_SHA256") | .value' |
    tr '[:upper:]' '[:lower:]')
fi

if [[ ! -f "$keystore" ]]; then
  if [[ -n "$pinned" ]]; then
    echo "Restore the backed-up Android release key before running setup." >&2
    exit 1
  fi
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
fingerprint=$(
  openssl pkcs12 -in "$keystore" -passin "file:$password" -clcerts -nokeys |
    openssl x509 -noout -sha256 -fingerprint |
    cut -d= -f2 | tr -d ':\r\n' | tr '[:upper:]' '[:lower:]'
)
if [[ ! "$fingerprint" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not read the Android signing certificate fingerprint." >&2
  exit 1
fi
echo "Android signing key ready in .signing/. Back up this folder for future app updates."

if [[ "${1:-}" == --local-only ]]; then
  exit 0
fi

# The certificate fingerprint is public. Keep an existing pin fixed so a
# different local key cannot silently invalidate upgrades on users' phones.
if [[ -n "$pinned" && "$pinned" != "$fingerprint" ]]; then
  echo "The Android signer differs from the repository pin. Restore the backed-up release key before continuing." >&2
  exit 1
fi
if [[ -z "$pinned" ]]; then
  gh api --method POST 'repos/{owner}/{repo}/actions/variables' --silent \
    -f name=GATEAHEAD_ANDROID_CERT_SHA256 -f "value=$fingerprint"
fi

# gh infers this mobile repository from its Git remote. Secret values stay off stdout.
base64 < "$keystore" | gh secret set GATEAHEAD_ANDROID_KEYSTORE_BASE64
tr -d '\r\n' < "$password" | gh secret set GATEAHEAD_ANDROID_KEYSTORE_PASSWORD
echo "Android signer pin verified and signing secrets uploaded to this repository."
