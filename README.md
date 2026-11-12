# GateAhead

Flutter client for the GateAhead API. iOS, Android, and Linux share this project. The Python API is a separate repository. Prediction stays there.

```bash
flutter pub get
flutter test
flutter run --dart-define=API_BASE=http://10.0.2.2:8000
```

Start the API with `uvicorn gateahead.api.app:app --host 0.0.0.0 --port 8000`.

- This Linux desktop: `flutter run -d linux --dart-define=API_BASE=http://127.0.0.1:8000`
- Android emulator: `http://10.0.2.2:8000`
- iOS simulator: `http://127.0.0.1:8000`
- A phone on the same Wi-Fi: `http://<this-computer-lan-ip>:8000`

The desktop build needs `clang`, `ninja-build`, `pkg-config`, and `libgtk-3-dev`.

`API_BASE` defaults to `http://127.0.0.1:8000`.
