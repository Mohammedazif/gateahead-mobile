#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${RUNNER_TEMP:?Use a dedicated macOS CI runner}"
: "${FIREBASE_CONFIG:?Missing Firebase iOS configuration}"
: "${FIREBASE_PROJECT:?Missing expected Firebase project}"
: "${SIGNING_CERTIFICATE:?Missing Apple Distribution certificate}"
: "${SIGNING_PASSWORD:?Missing certificate password}"
: "${PROVISIONING_PROFILE:?Missing iOS ad hoc profile}"
: "${GITHUB_RUN_NUMBER:?Missing build number}"
: "${API_BASE:?Missing GateAhead API address}"

push_config=ios/Flutter/Push.xcconfig
firebase_plist=ios/Runner/GoogleService-Info.plist
if [[ -e "$push_config" || -e "$firebase_plist" ]]; then
  echo "Use a clean checkout for the signed push build." >&2
  exit 1
fi

work=$(mktemp -d "$RUNNER_TEMP/gateahead-ios-push.XXXXXX")
keychain="$work/signing.keychain-db"
keychain_password=$(openssl rand -hex 24)
original_keychains=()
while IFS= read -r path; do
  path=${path#*\"}
  original_keychains+=("${path%\"*}")
done < <(security list-keychains -d user)
profile_destination=""
cleanup() {
  security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [[ -n "$profile_destination" ]]; then rm -f -- "$profile_destination"; fi
  rm -f -- "$push_config" "$firebase_plist"
  rm -rf -- "$work"
}
trap cleanup EXIT

printf '%s' "$FIREBASE_CONFIG" | base64 -D > "$firebase_plist"
printf '%s' "$SIGNING_CERTIFICATE" | base64 -D > "$work/distribution.p12"
printf '%s' "$PROVISIONING_PROFILE" | base64 -D > "$work/profile.mobileprovision"
security cms -D -i "$work/profile.mobileprovision" > "$work/profile.plist"

python3 - "$firebase_plist" "$work/profile.plist" "$work" <<'PY'
import os
import plistlib
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

firebase_path, profile_path, work = map(Path, sys.argv[1:])
firebase = plistlib.loads(firebase_path.read_bytes())
if (firebase.get("PROJECT_ID") != os.environ["FIREBASE_PROJECT"]
        or firebase.get("BUNDLE_ID") != "in.gateahead.app"
        or not firebase.get("GOOGLE_APP_ID")):
    raise SystemExit("Firebase options must match the configured project and GateAhead bundle ID")

profile = plistlib.loads(profile_path.read_bytes())
team, = profile["TeamIdentifier"]
uuid = profile["UUID"]
entitlements = profile["Entitlements"]
expiration = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
if (not re.fullmatch(r"[A-Z0-9]{10}", team)
        or not re.fullmatch(r"[A-Fa-f0-9-]{36}", uuid)
        or expiration <= datetime.now(timezone.utc)
        or not profile.get("ProvisionedDevices")
        or entitlements.get("get-task-allow", False)
        or entitlements.get("aps-environment") != "production"
        or entitlements.get("application-identifier") != f"{team}.in.gateahead.app"):
    raise SystemExit("Use an unexpired GateAhead ad hoc distribution profile with production Push Notifications")

(work / "profile-uuid").write_text(uuid)
Path("ios/Flutter/Push.xcconfig").write_text(
    "CODE_SIGN_STYLE = Manual\n"
    "CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution\n"
    f"DEVELOPMENT_TEAM = {team}\n"
    f"PROVISIONING_PROFILE_SPECIFIER = {uuid}\n"
    "CODE_SIGN_ENTITLEMENTS = Runner/Push.entitlements\n"
    "GATEAHEAD_APS_ENVIRONMENT = production\n"
)
(work / "ExportOptions.plist").write_bytes(plistlib.dumps({
    "method": "release-testing",
    "signingStyle": "manual",
    "signingCertificate": "Apple Distribution",
    "teamID": team,
    "provisioningProfiles": {"in.gateahead.app": uuid},
}))
PY

profile_directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_directory"
profile_path="$profile_directory/$(cat "$work/profile-uuid").mobileprovision"
if [[ -e "$profile_path" ]]; then
  echo "The signing profile already exists on this runner." >&2
  exit 1
fi
profile_destination="$profile_path"
cp "$work/profile.mobileprovision" "$profile_destination"

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/distribution.p12" -P "$SIGNING_PASSWORD" -k "$keychain" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"

flutter build ipa --release --build-number="$GITHUB_RUN_NUMBER" \
  --dart-define="API_BASE=$API_BASE" --export-options-plist="$work/ExportOptions.plist"

artifacts=(build/ios/ipa/*.ipa)
if [[ ${#artifacts[@]} -ne 1 || ! -f "${artifacts[0]}" ]]; then
  echo "Expected a single signed IPA." >&2
  exit 1
fi
unzip -q "${artifacts[0]}" -d "$work/ipa"
app="$work/ipa/Payload/Runner.app"
codesign --verify --deep --strict "$app"
codesign -d --entitlements :- "$app" > "$work/signed-entitlements.plist"
python3 - "$app" "$work/signed-entitlements.plist" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

app, signature = map(Path, sys.argv[1:])
firebase = plistlib.loads((app / "GoogleService-Info.plist").read_bytes())
info = plistlib.loads((app / "Info.plist").read_bytes())
entitlements = plistlib.loads(signature.read_bytes())
if (firebase.get("PROJECT_ID") != os.environ["FIREBASE_PROJECT"]
        or info.get("CFBundleIdentifier") != "in.gateahead.app"
        or entitlements.get("aps-environment") != "production"
        or entitlements.get("get-task-allow")):
    raise SystemExit("Signed IPA is missing the expected bundle, Firebase project or production APS entitlement")
PY
mkdir -p dist
cp "${artifacts[0]}" dist/gateahead-ios-push.ipa
