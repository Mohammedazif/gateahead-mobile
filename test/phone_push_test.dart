import "package:firebase_core_platform_interface/firebase_core_platform_interface.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:gateahead/phone_push.dart";

class _FixtureFirebase extends FirebasePlatform {
  final _app = FirebaseAppPlatform(
    defaultFirebaseAppName,
    const FirebaseOptions(
      apiKey: "fixture",
      appId: "fixture",
      messagingSenderId: "fixture",
      projectId: "fixture",
    ),
  );

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final granted in [true, false]) {
    test("iOS enrollment starts APNs after permission ($granted)", () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final originalFirebase = FirebasePlatform.instance;
      FirebasePlatform.instance = _FixtureFirebase();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel("plugins.flutter.io/firebase_messaging");
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        FirebasePlatform.instance = originalFirebase;
        messenger.setMockMethodCallHandler(channel, null);
      });

      const fid = "cTestRegistrationFixture";
      var autoInit = false;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case "Messaging#requestPermission":
            return {"authorizationStatus": granted ? 1 : 0};
          case "Messaging#setAutoInitEnabled":
            autoInit = (call.arguments as Map)["enabled"] as bool;
            return {"isAutoInitEnabled": autoInit};
          case "Messaging#getAPNSToken":
            return {"token": autoInit ? "fixture-apns" : null};
          case "Messaging#register":
            await messenger.handlePlatformMessage(
              channel.name,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall("Messaging#onRegistered", fid),
              ),
              null,
            );
            return null;
          case "Messaging#unregister":
            expect(autoInit, isFalse);
            return null;
          default:
            throw StateError("Unexpected call ${call.method}");
        }
      });

      final push = (await FirebasePhonePush.setup())!;
      expect(await push.requestInstallationId(), granted ? fid : null);
      if (granted) await push.disconnect();
      expect(calls, [
        "Messaging#requestPermission",
        if (granted) ...[
          "Messaging#setAutoInitEnabled",
          "Messaging#getAPNSToken",
          "Messaging#register",
          "Messaging#setAutoInitEnabled",
          "Messaging#unregister",
        ],
      ]);
    });
  }

  test("decodes fresh Android alerts and drops expired or proof messages", () {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final data = {
      "crossing_link": "https://gateahead.vercel.app/?lat=12&lon=75&gate=pin:1",
      "notification_id": "1031123",
      "title": "GateAhead crossing alert",
      "body": "A train may reach your saved crossing soon.",
      "expires_at": "${now + 120}",
    };
    final notice = CrossingNotification.fromMessage(RemoteMessage(data: data));
    expect(notice?.id, 1031123);
    expect(notice?.remaining.inSeconds, inInclusiveRange(100, 120));
    expect(
      CrossingNotification.fromMessage(
        RemoteMessage(data: {...data, "expires_at": "${now - 1}"}),
      ),
      isNull,
    );
    expect(
      CrossingNotification.fromMessage(
        const RemoteMessage(
          data: {
            "phone_alert_challenge_id": "challenge",
            "phone_alert_challenge": "response",
          },
        ),
      ),
      isNull,
    );
  });
}
