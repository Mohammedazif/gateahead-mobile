#!/usr/bin/env bash
set -euo pipefail

platform=${1:?Usage: publish-test-build.sh android|ios path-to-build}
asset=${2:?Pass the APK or IPA path}
test -s "$asset"

case "$platform" in
  android) label=Android ;;
  ios) label=iPhone ;;
  *) echo "Unknown platform: $platform" >&2; exit 1 ;;
esac

notes=$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gateahead-release.XXXXXX")
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<EOF
GateAhead phone test build from commit $GITHUB_SHA.

API: $API_BASE

- Android: download gateahead-android.apk on the phone and allow installation from that download source.
- iPhone: download gateahead-ios-unsigned.ipa on a Mac or Windows computer, then sign and install it using Sideloadly or AltStore with your own Apple ID. It cannot be installed by tapping it in Safari. Requires iOS 15 or later.
- A free Apple ID needs the iPhone app refreshed every seven days. No Apple credentials are stored in GitHub.

Build log: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
EOF

release_options=(--repo "$GITHUB_REPOSITORY" --latest=false)
if [[ "$GITHUB_REF_TYPE" == tag && "$GITHUB_REF_NAME" == v* ]]; then
  tag=$GITHUB_REF_NAME
  title="GateAhead $tag"
else
  tag="${platform}-latest"
  title="$label test build"
  release_options+=(--prerelease)
fi

if ! gh release view "$tag" --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1; then
  # Both platform workflows can create a versioned release at the same time.
  if ! gh release create "$tag" --target "$GITHUB_SHA" --title "$title" \
      --notes-file "$notes" "${release_options[@]}"; then
    gh release view "$tag" --repo "$GITHUB_REPOSITORY" > /dev/null
  fi
fi

gh release upload "$tag" "$asset" --clobber --repo "$GITHUB_REPOSITORY"

if [[ "$tag" == "${platform}-latest" ]]; then
  # Keep the rolling release's source tag aligned with the APK/IPA just uploaded.
  gh api --method PATCH "repos/$GITHUB_REPOSITORY/git/refs/tags/$tag" \
    -f sha="$GITHUB_SHA" -F force=true > /dev/null
  gh release edit "$tag" --title "$title" --notes-file "$notes" "${release_options[@]}"
fi
