import "dart:async";
import "dart:ui";

import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:shared_preferences/shared_preferences.dart";

import "device_store.dart";

abstract interface class PhonePushRegistration {
  Future<String?> requestInstallationId();
  Stream<String> get installationIdChanges;
  Future<bool> notificationPermission();
  Future<void> disconnect();
  Stream<PhoneAlertChallenge> get challenges;
}

class PhoneAlertChallenge {
  const PhoneAlertChallenge(this.id, this.response);
  final String id;
  final String response;
}

class PhonePushException implements Exception {
  const PhonePushException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _crossingLink(Object? value) {
  if (value is! String || value.length > 500) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != "https" || uri.userInfo.isNotEmpty) {
    return null;
  }
  final crossing = parseCrossingLink(value);
  if (crossing == null || (crossing.gateId?.isEmpty ?? true)) return null;
  return value;
}

class CrossingNotification {
  const CrossingNotification({
    required this.link,
    required this.title,
    required this.body,
    required this.id,
    required this.expiresAt,
  });

  final String link;
  final String title;
  final String body;
  final int id;
  final DateTime expiresAt;
  Duration get remaining => expiresAt.difference(DateTime.now());

  static CrossingNotification? fromMessage(RemoteMessage message) {
    final data = message.data;
    final link = _crossingLink(data["crossing_link"]);
    final title = data["title"], body = data["body"];
    final id = int.tryParse("${data["notification_id"]}");
    final expiry = int.tryParse("${data["expires_at"]}");
    if (link == null ||
        title is! String ||
        title.isEmpty ||
        title.length > 120 ||
        body is! String ||
        body.isEmpty ||
        body.length > 240 ||
        id == null ||
        id <= 0 ||
        id > 0x7fffffff ||
        expiry == null ||
        expiry <= 0 ||
        expiry > 4102444800) {
      return null;
    }
    final notice = CrossingNotification(
      link: link,
      title: title,
      body: body,
      id: id,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiry * 1000,
        isUtc: true,
      ),
    );
    return notice.remaining > Duration.zero ? notice : null;
  }
}

const _crossingChannel = AndroidNotificationChannel(
  "crossing_alerts",
  "Saved crossing alerts",
  description: "Estimated closure alerts for saved crossings",
  importance: Importance.high,
);

const _androidSettings = InitializationSettings(
  android: AndroidInitializationSettings("gateahead_icon_foreground"),
);
const _androidAlertConsent = "gateahead.android_alert_delivery_enabled";

@pragma("vm:entry-point")
Future<void> _displayBackgroundAlert(RemoteMessage message) async {
  final notice = CrossingNotification.fromMessage(message);
  if (notice == null) return;
  DartPluginRegistrant.ensureInitialized();
  // The Firebase background isolate can outlive a change in enrollment.
  if (await SharedPreferencesAsync().getBool(_androidAlertConsent) != true) {
    return;
  }
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(settings: _androidSettings);
  final remaining = notice.remaining;
  if (remaining <= Duration.zero) return;
  await notifications.show(
    id: notice.id,
    title: notice.title,
    body: notice.body,
    payload: notice.link,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _crossingChannel.id,
        _crossingChannel.name,
        channelDescription: _crossingChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
        timeoutAfter: remaining.inMilliseconds,
      ),
    ),
  );
}

class FirebasePhonePush implements PhonePushRegistration {
  FirebasePhonePush._(this._messaging, this._ios, this._androidNotifications);

  final FirebaseMessaging _messaging;
  final bool _ios;
  final FlutterLocalNotificationsPlugin? _androidNotifications;
  final _localLinks = StreamController<String>.broadcast();

  static Future<FirebasePhonePush?> setup() async {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    if (kIsWeb || (!ios && defaultTargetPlatform != TargetPlatform.android)) {
      return null;
    }
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 5));
      final local = ios ? null : FlutterLocalNotificationsPlugin();
      final push = FirebasePhonePush._(FirebaseMessaging.instance, ios, local);
      if (local != null) {
        await local
            .initialize(
              settings: _androidSettings,
              onDidReceiveNotificationResponse: (response) {
                final link = _crossingLink(response.payload);
                if (link != null) push._localLinks.add(link);
              },
            )
            .timeout(const Duration(seconds: 5));
        final android = local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android
            ?.createNotificationChannel(_crossingChannel)
            .timeout(const Duration(seconds: 5));
        FirebaseMessaging.onBackgroundMessage(_displayBackgroundAlert);
      }
      return push;
    } on FirebaseException catch (error) {
      if (error.code != "not-initialized") {
        debugPrint(
          "Could not initialize GateAhead notifications (${error.code}).",
        );
      }
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static bool _authorized(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  @override
  Future<bool> notificationPermission() async {
    if (!_authorized(await _messaging.getNotificationSettings())) return false;
    final android = _androidNotifications
        ?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final channels = await android?.getNotificationChannels();
    return !(channels ?? []).any(
      (channel) =>
          channel.id == _crossingChannel.id &&
          channel.importance == Importance.none,
    );
  }

  @override
  Future<String?> requestInstallationId() async {
    if (!_authorized(await _messaging.requestPermission())) return null;

    final registered = Completer<String?>();
    final listener = installationIdChanges.listen(
      (id) {
        if (!registered.isCompleted) registered.complete(id);
      },
      onError: (Object _) {
        if (!registered.isCompleted) registered.complete(null);
      },
    );
    try {
      if (_ios) {
        // On a fresh iPhone, this starts APNs only after the user consents.
        await _messaging
            .setAutoInitEnabled(true)
            .timeout(const Duration(seconds: 5));
        final deadline = Stopwatch()..start();
        while (await _messaging.getAPNSToken().timeout(
              const Duration(seconds: 2),
            ) ==
            null) {
          if (deadline.elapsed >= const Duration(seconds: 8)) {
            throw const PhonePushException(
              "Apple push registration did not finish. Try again shortly.",
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
      await _messaging.register().timeout(const Duration(seconds: 12));
      final id = await registered.future.timeout(const Duration(seconds: 12));
      if (id == null || id.isEmpty) {
        throw const PhonePushException(
          "The notification provider did not confirm registration.",
        );
      }
      if (!_ios) {
        await _messaging
            .setAutoInitEnabled(true)
            .timeout(const Duration(seconds: 5));
        await SharedPreferencesAsync().setBool(_androidAlertConsent, true);
      }
      return id;
    } on TimeoutException {
      throw const PhonePushException(
        "Notification registration timed out. Try again shortly.",
      );
    } on FirebaseException {
      throw const PhonePushException(
        "The notification provider could not register this phone.",
      );
    } finally {
      await listener.cancel();
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      if (!_ios) {
        await SharedPreferencesAsync().setBool(_androidAlertConsent, false);
      }
    } finally {
      await _unregister();
    }
  }

  Future<void> _unregister() async {
    try {
      await _messaging
          .setAutoInitEnabled(false)
          .timeout(const Duration(seconds: 5));
      await _messaging.unregister().timeout(const Duration(seconds: 12));
    } finally {
      await _androidNotifications?.cancelAll();
    }
  }

  @override
  Stream<String> get installationIdChanges => _messaging.onRegistered;

  @override
  Stream<PhoneAlertChallenge> get challenges => FirebaseMessaging.onMessage
      .map((message) {
        final id = message.data["phone_alert_challenge_id"];
        final response = message.data["phone_alert_challenge"];
        if (id is! String ||
            id.isEmpty ||
            id.length > 120 ||
            response is! String ||
            response.isEmpty ||
            response.length > 160) {
          return null;
        }
        return PhoneAlertChallenge(id, response);
      })
      .where((challenge) => challenge != null)
      .cast<PhoneAlertChallenge>();

  Stream<CrossingNotification> get foreground => FirebaseMessaging.onMessage
      .map(CrossingNotification.fromMessage)
      .where((notice) => notice != null && _messaging.isAutoInitEnabled)
      .cast<CrossingNotification>();

  Stream<String> get opened => Stream.multi((controller) {
    final remote = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final link = _crossingLink(message.data["crossing_link"]);
      if (link != null) controller.add(link);
    });
    final local = _localLinks.stream.listen(controller.add);
    controller.onCancel = () async {
      await remote.cancel();
      await local.cancel();
    };
  });

  Future<String?> initialLink() async {
    try {
      final local = await _androidNotifications
          ?.getNotificationAppLaunchDetails();
      if (local?.didNotificationLaunchApp == true) {
        final link = _crossingLink(local?.notificationResponse?.payload);
        if (link != null) return link;
      }
      return _crossingLink(
        (await _messaging.getInitialMessage())?.data["crossing_link"],
      );
    } on FirebaseException catch (error) {
      debugPrint("Could not open the GateAhead notification (${error.code}).");
    } on PlatformException {
      debugPrint("Could not open the GateAhead notification.");
    }
    return null;
  }
}
