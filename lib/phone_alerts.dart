import "dart:async";
import "dart:math";

import "package:flutter/foundation.dart";

import "api.dart";
import "device_store.dart";
import "phone_push.dart";

class PhoneAlertSettings {
  const PhoneAlertSettings({
    this.leadMinutes = 10,
    this.startMinute = 480,
    this.endMinute = 600,
    this.weekdaysOnly = true,
  });

  final int leadMinutes, startMinute, endMinute;
  final bool weekdaysOnly;

  bool get allDay => startMinute == endMinute;

  PhoneAlertSettings copyWith({
    int? leadMinutes,
    int? startMinute,
    int? endMinute,
    bool? weekdaysOnly,
  }) => PhoneAlertSettings(
    leadMinutes: leadMinutes ?? this.leadMinutes,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    weekdaysOnly: weekdaysOnly ?? this.weekdaysOnly,
  );

  Map<String, Object> toJson() => {
    "lead_minutes": leadMinutes,
    "start_minute": startMinute,
    "end_minute": endMinute,
    "weekdays_only": weekdaysOnly,
  };

  static PhoneAlertSettings? tryParse(Object? value) {
    if (value is! Map) return null;
    final lead = value["lead_minutes"];
    final start = value["start_minute"], end = value["end_minute"];
    if (lead is! int ||
        !const [5, 10, 15].contains(lead) ||
        start is! int ||
        start < 0 ||
        start > 1439 ||
        end is! int ||
        end < 0 ||
        end > 1439 ||
        value["weekdays_only"] is! bool) {
      return null;
    }
    return PhoneAlertSettings(
      leadMinutes: lead,
      startMinute: start,
      endMinute: end,
      weekdaysOnly: value["weekdays_only"],
    );
  }
}

class PhoneAlerts extends ChangeNotifier {
  PhoneAlerts(RailApi api, this.storage, this.push, this._favorites)
    : _api = api is PhoneAlertsApi ? api as PhoneAlertsApi : null {
    final raw = storage?.read("phone-alerts");
    if (raw is Map) {
      final prefs = raw["gates"];
      if (prefs is Map) {
        for (final entry in prefs.entries.take(maxGates)) {
          final settings = PhoneAlertSettings.tryParse(entry.value);
          if (entry.key is String && settings != null) {
            _settings[entry.key] = settings;
          }
        }
      }
      pending = raw["pending"] == true;
      _fid = raw["fid"] is String ? raw["fid"] : null;
      _lastSync = storedDateTime(raw["synced_at"]);
      _revision = _savedRevision(raw["revision"]) ?? 0;
      _conflictRevision = _savedRevision(raw["conflict_revision"]);
      _disconnectPending = raw["disconnect_pending"] == true;
      final storedKey = raw["device_key"];
      if (storedKey is String &&
          RegExp(r"^[0-9a-f]{64}$").hasMatch(storedKey)) {
        _deviceKey = storedKey;
      } else if (hasAlerts) {
        pending = true;
      }
      if (hasAlerts && _revision == 0) pending = true;
    }
    _registrationChanges = push?.installationIdChanges.listen(
      _rotate,
      onError: (Object _) {},
    );
  }

  static const maxGates = 5;
  static const _maxRevision = 9007199254740991;
  static int? _savedRevision(Object? value) =>
      value is int && value >= 0 && value <= _maxRevision ? value : null;

  final PhoneAlertsApi? _api;
  final DeviceStore? storage;
  final PhonePushRegistration? push;
  final List<SavedGate> Function() _favorites;
  final Map<String, PhoneAlertSettings> _settings = {};
  StreamSubscription<String>? _registrationChanges;
  String? _fid, _deviceKey;
  DateTime? _lastSync;
  bool _requestingRegistration = false;
  bool _disconnectPending = false;
  int _intent = 0;
  int _revision = 0;
  int? _conflictRevision;
  Completer<void>? _cancelChallenge;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;
  bool pending = false;
  bool saving = false;
  bool? devicePermission;
  PhoneAlertStatus? serviceStatus;
  String? message;

  bool get canSetUp => _api != null && storage != null && push != null;
  bool get showControls =>
      canSetUp || pending || hasAlerts || _disconnectPending;
  bool get hasAlerts => _settings.isNotEmpty;
  bool get needsAttention =>
      pending ||
      _disconnectPending ||
      message != null ||
      hasAlerts &&
          (devicePermission == false || serviceStatus?.health == "degraded");
  int get count => _settings.length;
  DateTime? get lastConfirmedAt => _lastSync;
  PhoneAlertSettings? settingsFor(String id) => _settings[id];

  String get badge {
    if (devicePermission == false) return "device permission off";
    if (pending) return "pending sync";
    if (saving) return "checking registration";
    if (serviceStatus case final status?) {
      if (!status.enabled || status.health == "degraded") {
        return "service unavailable";
      }
      if (status.health == "starting") return "service starting";
      if (status.registered != count || !status.fidVerified) {
        return "registration needs checking";
      }
      if (devicePermission == true) return "registered";
    }
    return "status unconfirmed";
  }

  Future<void> save(SavedGate gate, PhoneAlertSettings settings) async {
    if (!canSetUp || saving || isLegacyCrossingId(gate.gate.id)) return;
    if (!_favorites().any((row) => row.gate.id == gate.gate.id)) return;
    if (!_settings.containsKey(gate.gate.id) && count >= maxGates) return;
    _settings[gate.gate.id] = settings;
    _disconnectPending = false;
    _markPending();
    await sync(interactive: true);
  }

  Future<void> remove(String id) async {
    if (_settings.remove(id) == null) return;
    _markPending();
    await sync(interactive: true, promptForPermission: false);
  }

  Future<void> disconnect() async {
    _settings.clear();
    _markPending();
    await sync(interactive: true);
  }

  void reconcileSavedGates() {
    final saved = {for (final row in _favorites()) row.gate.id};
    final countBefore = count;
    _settings.removeWhere((id, _) => !saved.contains(id));
    if (count != countBefore) {
      _markPending();
      unawaited(sync());
    }
  }

  void replaceGate(String oldId, String newId) {
    final settings = _settings.remove(oldId);
    if (settings == null) return;
    _settings.putIfAbsent(newId, () => settings);
    _markPending();
    unawaited(sync());
  }

  void _rotate(String fid) {
    // register() emits the same ID it returns to an interactive caller.
    if (_disposed ||
        !hasAlerts ||
        _requestingRegistration ||
        fid.isEmpty ||
        _fid == fid) {
      return;
    }
    _fid = fid;
    _markPending();
    unawaited(sync());
  }

  void _markPending() {
    if (!hasAlerts && push != null) _disconnectPending = true;
    pending = true;
    _intent++;
    if (_revision < _maxRevision) _revision++;
    final cancel = _cancelChallenge;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    unawaited(_persist());
    notifyListeners();
  }

  Future<bool> _persist() async {
    final snapshot = {
      "gates": {
        for (final row in _settings.entries) row.key: row.value.toJson(),
      },
      "pending": pending,
      "device_key": _deviceKey,
      "fid": _fid,
      "synced_at": _lastSync?.millisecondsSinceEpoch,
      "revision": _revision,
      "conflict_revision": _conflictRevision,
      "disconnect_pending": _disconnectPending,
    };
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    await previous;
    try {
      return await storage?.write("phone-alerts", snapshot) ?? false;
    } finally {
      done.complete();
    }
  }

  String _newDeviceKey() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, "0"),
    ).join();
  }

  Future<void> resume() => sync();

  Future<String?> _requestRegistration() async {
    _requestingRegistration = true;
    try {
      return await push?.requestInstallationId();
    } finally {
      _requestingRegistration = false;
    }
  }

  Future<PhoneAlertChallenge?> _verify(
    PhoneAlertsApi api,
    String key,
    String fid,
    int revision,
    int intent,
  ) async {
    final bridge = push;
    if (bridge == null) return null;
    final proof = Completer<PhoneAlertChallenge?>();
    final cancel = Completer<void>();
    _cancelChallenge = cancel;
    final early = <String, PhoneAlertChallenge>{};
    String? expected;
    final subscription = bridge.challenges.listen(
      (challenge) {
        if (expected == null && early.length < 8) {
          early[challenge.id] = challenge;
        }
        if (challenge.id == expected && !proof.isCompleted) {
          proof.complete(challenge);
        }
      },
      onError: (Object _) {
        if (!proof.isCompleted) proof.complete(null);
      },
    );
    try {
      final request = await api.challengePhoneAlerts(key, fid, revision);
      if (_disposed || intent != _intent) return null;
      expected = request.id;
      return early[expected] ??
          await Future.any([proof.future, cancel.future.then((_) => null)])
              .timeout(request.ttl, onTimeout: () => null);
    } finally {
      if (identical(_cancelChallenge, cancel)) _cancelChallenge = null;
      await subscription.cancel();
    }
  }

  Future<void> _stopRegistration(int intent) async {
    final bridge = push;
    if (!_disconnectPending || bridge == null) return;
    try {
      await bridge.disconnect().timeout(const Duration(seconds: 20));
      if (!_disposed && intent == _intent) _disconnectPending = false;
    } catch (_) {
      // Leave the local cleanup pending even if server revocation can finish.
    }
  }

  Future<void> sync({
    bool interactive = false,
    bool promptForPermission = true,
  }) async {
    final api = _api;
    if (_disposed ||
        api == null ||
        saving ||
        (!hasAlerts && !pending && !_disconnectPending)) {
      return;
    }
    final intent = _intent;
    saving = true;
    message = null;
    if (hasAlerts) serviceStatus = null;
    notifyListeners();
    bool current() => !_disposed && intent == _intent;
    final stopping = !hasAlerts ? _stopRegistration(intent) : null;
    try {
      final savedById = {for (final gate in _favorites()) gate.gate.id: gate};
      final desired = [
        for (final entry in _settings.entries)
          if (savedById[entry.key] case final SavedGate saved)
            {
              "crossing_id": saved.gate.id,
              "lat": saved.gate.lat,
              "lon": saved.gate.lon,
              ...entry.value.toJson(),
            },
      ];
      if (desired.isEmpty && _deviceKey == null) {
        pending = false;
        return;
      }
      if (desired.isEmpty && !pending) return;
      if (_conflictRevision != null) {
        if (!interactive) throw PhoneAlertConflict(_conflictRevision!);
        if (_conflictRevision! > _revision) _revision = _conflictRevision!;
        if (_revision >= _maxRevision) {
          throw RailException(
            "Phone alert settings require a new installation.",
          );
        }
        _revision++;
        _conflictRevision = null;
      }
      _deviceKey ??= _newDeviceKey();
      final key = _deviceKey!;
      PhoneAlertChallenge? challenge;
      if (desired.isNotEmpty) {
        final bridge = push;
        if (bridge == null) {
          throw RailException("Phone alerts are unavailable on this device.");
        }
        try {
          final allowed = await bridge.notificationPermission();
          if (!current()) return;
          devicePermission = allowed;
        } catch (_) {
          if (!current()) return;
          devicePermission = null;
        }
        final status = await api.phoneAlertStatus(key, _fid);
        if (!current()) return;
        serviceStatus = status;
        if (!status.enabled) {
          throw RailException("Phone alerts are unavailable on this service.");
        }
        if (status.revision > _revision) {
          throw PhoneAlertConflict(status.revision);
        }
        final reducing =
            status.fidVerified && status.registered > desired.length;
        final mayPrompt = interactive && promptForPermission;
        if (!mayPrompt && devicePermission != true && !reducing) {
          message = "Allow notifications in device settings, then retry.";
          return;
        }
        final renew =
            _lastSync == null ||
            DateTime.now().difference(_lastSync!) >= const Duration(days: 7);
        if (!pending &&
            !renew &&
            status.registered == desired.length &&
            status.fidVerified &&
            status.revision == _revision) {
          return;
        }
        if (!pending) {
          pending = true;
          if (_revision < _maxRevision) _revision++;
        }
        if (mayPrompt || _fid == null || !status.fidVerified) {
          final fid = await _requestRegistration();
          if (!current()) return;
          final allowed =
              fid != null &&
              fid.isNotEmpty &&
              await bridge.notificationPermission();
          if (!current()) return;
          devicePermission = allowed;
          if (!allowed) {
            throw RailException(
              "Allow notifications in device settings, then retry.",
            );
          }
          if (_fid != null &&
              _fid != fid &&
              status.revision == _revision &&
              _revision < _maxRevision) {
            _revision++;
          }
          final needsVerification = !status.fidVerified || _fid != fid;
          _fid = fid;
          if (needsVerification) {
            if (_revision == 0) _revision = 1;
            if (!await _persist()) {
              throw RailException(
                "Could not store phone alert settings on this device.",
              );
            }
            if (!current()) return;
            challenge = await _verify(api, key, fid, _revision, intent);
            if (!current()) return;
            if (challenge == null) {
              throw RailException(
                "Phone verification did not arrive. Keep GateAhead open and try again.",
              );
            }
          }
        }
      }
      if (_revision == 0) _revision = 1;
      if (!await _persist()) {
        throw RailException(
          "Could not store phone alert settings on this device.",
        );
      }
      if (!current()) return;
      final response = await api.updatePhoneAlerts(
        deviceKey: key,
        fid: desired.isEmpty ? null : _fid,
        revision: _revision,
        gates: desired,
        challengeId: challenge?.id,
        challengeResponse: challenge?.response,
      );
      if (!current()) return;
      serviceStatus = response;
      if (response.revision != _revision ||
          response.registered != desired.length ||
          desired.isNotEmpty && (!response.enabled || !response.fidVerified)) {
        throw RailException(
          "The service could not confirm your alert settings. Try again.",
        );
      }
      pending = false;
      _lastSync = desired.isEmpty ? null : DateTime.now();
      if (desired.isEmpty) _fid = null;
    } on PhoneAlertConflict catch (error) {
      if (current()) {
        _conflictRevision = error.revision;
        pending = true;
        message = error.message;
      }
    } on PhonePushException catch (error) {
      if (current()) message = error.message;
    } on RailException catch (error) {
      if (current()) message = error.message;
    } catch (_) {
      if (current()) message = "Could not sync phone alerts. Try again.";
    } finally {
      await stopping;
      if (!_disposed) {
        if (current() && _disconnectPending && message == null) {
          message =
              "Phone notification cleanup is pending. Retry on this device.";
        }
        await _persist();
        if (!_disposed) {
          saving = false;
          notifyListeners();
          if (intent != _intent) unawaited(sync());
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final cancel = _cancelChallenge;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    unawaited(_registrationChanges?.cancel());
    super.dispose();
  }
}
