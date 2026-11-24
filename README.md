# GateAhead

Flutter client for the GateAhead API. iOS, Android, and Linux share this project. The Python API is a separate repository. Prediction stays there.

## Build phone apps with GitHub

The **Android app** and **iPhone app** workflows build this Flutter project and publish downloads under [Releases](https://github.com/Mohammedazif/gateahead-mobile/releases), like Roostling.

Both workflows use Flutter 3.47.9 and call `https://gateahead-api.onrender.com`. To use another server, set the repository's **Settings → Secrets and variables → Actions → Variables → API_BASE** to its public HTTPS address, without a trailing `/api`. The backend must be running for city search, gates, and train predictions to work.

### One-time Android signing setup

Run this from the `mobile` repository on a computer with OpenSSL and an authenticated [GitHub CLI](https://cli.github.com/):

```bash
bash tools/setup-android-signing.sh
```

This creates a password-protected signing key in the ignored `.signing/` folder and uploads `GATEAHEAD_ANDROID_KEYSTORE_BASE64` and `GATEAHEAD_ANDROID_KEYSTORE_PASSWORD` as repository secrets. It also records the public certificate fingerprint in the `GATEAHEAD_ANDROID_CERT_SHA256` repository variable. The release workflow checks the APK against that fingerprint before publishing. If the app has already been released, restore the original signing key from your backup before running the script to set the pin. Back up `.signing/` for future updates. For offline key creation, pass `--local-only`, then run the command without that flag when GitHub is reachable.

### Android test

1. Push these files to the repository's default branch.
2. Open **Actions → Android app → Run workflow** and select `main`.
3. Once it succeeds, open the [Android test release](https://github.com/Mohammedazif/gateahead-mobile/releases/tag/android-latest).
4. Download `gateahead-android.apk` on your Android phone, open it, and allow installation from your browser or file manager when asked.

The APK uses a permanent signing key so subsequent builds can update the installed app. If an earlier debug build is already installed with the same app ID, uninstall it before installing this signed build.

### iPhone test

1. Open **Actions → iPhone app → Run workflow** and select `main`.
2. Once it succeeds, download `gateahead-ios-unsigned.ipa` from the [iPhone test release](https://github.com/Mohammedazif/gateahead-mobile/releases/tag/ios-latest) onto a Mac or Windows computer.
3. Connect your iPhone and open the IPA in [Sideloadly](https://sideloadly.io/) or [AltStore](https://faq.altstore.io/altstore-classic/how-to-use-altstore).
4. Sign and install it using your own Apple ID. Trust the developer profile under **Settings → General → VPN & Device Management** and enable **Settings → Privacy & Security → Developer Mode** if prompted.

Requires iOS 15 or later. The IPA is a device build; it needs signing before installation and cannot be installed just by tapping the file in Safari. A free Apple ID works for personal testing, with refresh required every seven days. Apple credentials stay on your computer; no Apple signing secrets are required by the workflow. Sideloadly is available for macOS and Windows, so a Linux-only setup needs access to one of those computers for installation. TestFlight would require a separate Apple Developer distribution setup.

Both workflows also run when a `v*` tag is pushed, uploading their files to the same versioned release. Manual builds update the respective `android-latest` and `ios-latest` prereleases. Downloads go directly to Releases rather than Actions artifact storage.

## Local development

```bash
flutter pub get
flutter test
flutter run --dart-define=API_BASE=http://10.0.2.2:8000
```

Start the API with `uvicorn gateahead.api.app:app --host 0.0.0.0 --port 8000`.

On Linux sandboxes with a read-only Flutter SDK or blocked local sockets, run `python3 tools/check-sandboxed.py`. It compiles every test with the installed SDK, uses Flutter's standalone test runner, and analyzes the app and tests through the cached analyzer. Dependencies must already be installed; it downloads nothing and writes temporary compiler output under `/tmp`. Pass `--flutter-root /path/to/flutter` if Flutter is not on `PATH`.

- This Linux desktop: `flutter run -d linux --dart-define=API_BASE=http://127.0.0.1:8000`
- Android emulator: `http://10.0.2.2:8000`
- iOS simulator: `http://127.0.0.1:8000`
- A phone on the same Wi-Fi: `http://<this-computer-lan-ip>:8000`

The desktop build needs `clang`, `ninja-build`, `pkg-config`, and `libgtk-3-dev`.

Debug builds default to `http://127.0.0.1:8000`. Release builds require an HTTPS API address and default to `https://gateahead-api.onrender.com`.

## Navigation

Search for a place above the map. The panel has separate **Nearby**, **Trains**, and **Saved** views; selecting a crossing opens its details. Settings holds the theme, automatic checks, and commute hours. Reporting opens its own sheet. Drag or tap the panel handle to make more room for the map or the list.

Nearby markers use each gate's individual prediction, keep its own name, and do not copy a cluster ETA to every gate. Scene caches are refreshed when a newer nearby check exists. The crossing timing and next-train list use the same scene check. Train markers are hidden for reports at least eight minutes old and for positions outside the displayed track segment. The backend must provide `position_on_segment` before a train marker can appear.

## Saved gates, sharing, and offline results

Select a gate to save or rename it, copy its crossing link, and submit an unverified community report. Saved gates and successful API results stay on the device. Use **Open shared crossing link** to paste a GateAhead or OpenStreetMap link.

Copied links use `https://gateahead.vercel.app/` by default. Override this with `--dart-define=WEB_BASE=https://your-site.example/` when building against another website.

Optional automatic checks run every two minutes while the app is visible, with weekday and commute-hour controls in local device time. Manual train checks have a 90-second cooldown. Server rate limits pause further checks, and repeated scene opens reuse a result for 90 seconds.

Use **Settings → Clear location history** to remove the last place and cached checks on this device while keeping explicitly saved gates.

Cached predictions retain their original check time and are labeled as saved results. Stale train markers are suppressed and map tiles still need a connection. Community reports expire after ten minutes and remain separate from train predictions. Deploy a backend with `GET /reports` and `POST /reports` before using reports.

## Saved-gate phone alerts

From **Saved**, open a crossing's menu and choose **Phone alerts** to set a 5, 10 or 15 minute warning window and hours in India time. The phone build and API must use the same Firebase project. A notification opens the crossing when tapped.

- Android uses `android/app/google-services.json` downloaded for application ID `in.gateahead.app`. Copy it to that path before building. [Firebase Android setup](https://firebase.google.com/docs/android/setup)
- iOS uses `ios/Runner/GoogleService-Info.plist` downloaded for bundle ID `in.gateahead.app`. Upload the APNs authentication key to the Firebase project, then create the following local Xcode configuration. Use `development` for a development provisioning profile and `production` for a distribution profile. [Firebase Apple push setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)

`ios/Flutter/Push.xcconfig`

```xcconfig
CODE_SIGN_ENTITLEMENTS = Runner/Push.entitlements
GATEAHEAD_APS_ENVIRONMENT = development
```

The iOS push build needs a signing profile that grants the push notification entitlement. Builds without the Firebase configuration can still use saved gates, commute checks and the other crossing features.

For a signed GitHub Actions test build, set the repository variable `GATEAHEAD_FIREBASE_PROJECT_ID` to the shared Firebase project. Add the credentials as repository secrets and select **Enable push** when running the corresponding workflow. The signed push builds appear in the workflow's artifacts.

| Workflow | Additional secrets |
| --- | --- |
| Android | `GATEAHEAD_ANDROID_FIREBASE_CONFIG_BASE64` |
| iOS | `GATEAHEAD_IOS_FIREBASE_CONFIG_BASE64`, `GATEAHEAD_IOS_CERTIFICATE_BASE64`, `GATEAHEAD_IOS_CERTIFICATE_PASSWORD`, `GATEAHEAD_IOS_PROFILE_BASE64` |

Use an Apple Distribution certificate and an ad hoc profile with the test devices registered and production Push Notifications enabled. Verify a fresh install on each platform by granting permission, saving an alert while the app is open, then receiving a crossing alert in the background and opening it. Also verify that revoking alerts or denying permission is reflected in **Settings**.

Configure server credentials as described under [Saved-gate phone alerts in the API README](../backend/README.md#saved-gate-phone-alerts).

The Crossing Pin logo masters and header images are in `assets/branding/`. Android uses the matching launcher PNGs and adaptive icon resources in `android/app/src/main/res/`; iOS uses the opaque PNGs in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`. Rebuild the app to update its launcher icon.

The complete reusable logo kit is maintained in the frontend repository at `branding/gateahead-logo-kit/`, with an accompanying `branding/gateahead-logo-kit-v1.zip` backup. In a combined workspace it is available at `../frontend/branding/`. It includes Android/iOS icon sets, six vector variants, print formats, and raster exports from 16 to 4096px, plus scripts for other sizes. The kit's `README.md` explains each format.

Journey instances use `run_id` and `start_date` so overlapping runs of the same train remain separate in train lists, gate checks and stale-report handling. Origin dates are displayed alongside train numbers. Backend `service_updates` show cancellations, diversions and partial cancellations without normal-route closure countdowns. A newer check replaces the affected journey while preserving other dates of the same service.
