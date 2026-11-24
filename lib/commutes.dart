import "dart:async";

import "package:flutter/foundation.dart";

import "api.dart";
import "device_store.dart";
import "format.dart";
import "models.dart";
import "timing.dart";

class SavedCommute {
  const SavedCommute(this.id, this.name, this.gateIds);

  static const maxTrips = 12;
  static const maxGates = 6;
  final String id, name;
  final List<String> gateIds;

  Map<String, Object> toJson() => {"id": id, "name": name, "gates": gateIds};

  static SavedCommute? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw["id"], name = raw["name"], gates = raw["gates"];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        gates is! List) {
      return null;
    }
    final ids = gates.whereType<String>().where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return null;
    return SavedCommute(id, name.trim(), ids.take(maxGates).toList());
  }
}

class CommuteGateCheck {
  const CommuteGateCheck(this.gateId, {this.scene, this.at, this.error});

  final String gateId;
  final Scene? scene;
  final DateTime? at;
  final String? error;

  bool get historical =>
      scene?.offline == true ||
      error != null ||
      (at != null &&
          DateTime.now().difference(at!) >= const Duration(minutes: 2));

  Scene? get _display =>
      historical ? scene : currentScene(scene, DateTime.now());

  SceneTrain? get nextTrain => _display?.trains.firstOrNull;
  bool get awaitingReport => _display?.awaitingUpdate.isNotEmpty == true;

  String? get notice {
    if (scene == null) return null;
    final notes = [
      if (awaitingReport)
        historical
            ? "A train's position was unresolved at check."
            : "A train needs a position update. Barrier timing is unknown.",
      if (scene!.incomplete)
        historical
            ? "That train check was incomplete."
            : "Some train checks are incomplete.",
      ?error,
    ];
    return notes.isEmpty ? null : notes.join(" ");
  }

  String get summary {
    final snap = _display;
    if (snap == null) return error ?? "Crossing check unavailable";
    final lead = snap.trains.firstOrNull;
    if (lead != null) {
      final label = sceneTimingLabel(
        lead,
        snap,
        DateTime.now(),
        historical: historical,
      );
      return historical ||
              lead.observed == false ||
              label.startsWith("Estimated")
          ? label
          : "Estimated · $label";
    }
    if (snap.incomplete || snap.awaitingUpdate.isNotEmpty) {
      return historical
          ? "Timing was unknown at check."
          : "Status unknown · incomplete train check";
    }
    return "No approaching train was reported for this track.";
  }

  CommuteGateCheck forGate(String id) =>
      CommuteGateCheck(id, scene: scene, at: at, error: error);

  CommuteGateCheck afterFailure(String message) =>
      CommuteGateCheck(gateId, scene: scene, at: at, error: message);
}

class CommuteChecks extends ChangeNotifier {
  CommuteChecks(
    this.api,
    this.storage,
    this._onPause, {
    required List<SavedGate> favorites,
    this.onAlias,
  }) {
    final saved = storage?.read("commutes");
    if (saved is! List) return;
    final gates = {for (final row in favorites) row.gate.id: row};
    final valid = <String, SavedCommute>{};
    for (final row in saved.take(SavedCommute.maxTrips)) {
      final trip = SavedCommute.tryParse(row);
      if (trip == null) continue;
      final ids = trip.gateIds.where(gates.containsKey).toList();
      if (ids.isEmpty) continue;
      valid[trip.id] = SavedCommute(trip.id, trip.name, ids);
      final resultsForTrip = <String, CommuteGateCheck>{};
      for (final id in ids) {
        final gate = gates[id]!;
        final cached = storage?.response(
          sceneResponseKey(gate.place.lat, gate.place.lon, id),
        );
        if (cached == null) continue;
        final scene = Scene.parse(cached.restored());
        if (scene.available && scene.crossing != null) {
          resultsForTrip[id] = CommuteGateCheck(
            id,
            scene: scene,
            at: cached.at,
          );
        }
      }
      if (resultsForTrip.isNotEmpty) results[trip.id] = resultsForTrip;
    }
    trips = valid.values.toList();
  }

  final RailApi api;
  final DeviceStore? storage;
  final void Function(DateTime) _onPause;
  final void Function(SavedGate, SceneCrossing)? onAlias;
  List<SavedCommute> trips = [];
  final Map<String, Map<String, CommuteGateCheck>> results = {};
  DateTime? startedAt;
  String? checking;
  String? message, storageMessage;
  Completer<void>? _abort;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  Future<bool> save(
    String name,
    List<String> gateIds, {
    SavedCommute? original,
  }) async {
    final normalized = name.trim();
    final unique = gateIds.toSet().take(SavedCommute.maxGates).toList();
    if (_disposed || normalized.isEmpty || unique.isEmpty) return false;
    if (original == null && trips.length >= SavedCommute.maxTrips) return false;
    final trip = SavedCommute(
      original?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      normalized,
      unique,
    );
    if (original == null) {
      trips = [...trips, trip];
    } else {
      if (!trips.any((row) => row.id == trip.id)) return false;
      if (checking == trip.id) cancelCheck();
      trips = [for (final row in trips) row.id == trip.id ? trip : row];
      results[trip.id]?.removeWhere((id, _) => !unique.contains(id));
    }
    return _save();
  }

  void remove(SavedCommute trip) {
    if (checking == trip.id) cancelCheck();
    trips = trips.where((row) => row.id != trip.id).toList();
    results.remove(trip.id);
    unawaited(_save());
  }

  void replaceGate(String oldId, String newId) {
    if (!trips.any((trip) => trip.gateIds.contains(oldId))) return;
    trips = [
      for (final trip in trips)
        if (trip.gateIds.contains(oldId))
          SavedCommute(
            trip.id,
            trip.name,
            {for (final id in trip.gateIds) id == oldId ? newId : id}.toList(),
          )
        else
          trip,
    ];
    for (final result in results.values) {
      final previous = result.remove(oldId);
      if (previous != null) {
        result.putIfAbsent(newId, () => previous.forGate(newId));
      }
    }
    unawaited(_save());
  }

  void reconcileSavedGates(List<SavedGate> favorites) {
    final ids = {for (final row in favorites) row.gate.id};
    if (trips.every((trip) => trip.gateIds.every(ids.contains))) return;
    if (trips.any(
      (trip) => trip.id == checking && !trip.gateIds.every(ids.contains),
    )) {
      cancelCheck();
    }
    trips = [
      for (final trip in trips)
        if (trip.gateIds.any(ids.contains))
          SavedCommute(
            trip.id,
            trip.name,
            trip.gateIds.where(ids.contains).toList(),
          ),
    ];
    final active = {for (final trip in trips) trip.id};
    results.removeWhere((id, _) => !active.contains(id));
    for (final result in results.values) {
      result.removeWhere((id, _) => !ids.contains(id));
    }
    unawaited(_save());
  }

  Future<bool> _save() async {
    notifyListeners();
    final store = storage;
    if (store == null) return true;
    final snapshot = [for (final trip in trips) trip.toJson()];
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    await previous;
    try {
      final saved = await store.write("commutes", snapshot);
      if (!_disposed) {
        storageMessage = saved ? null : "Could not save commute changes. They are available for this session.";
        notifyListeners();
      }
      return saved;
    } finally {
      done.complete();
    }
  }

  void cancelCheck() {
    final abort = _abort;
    if (abort == null) return;
    _abort = null;
    checking = null;
    abort.complete();
    notifyListeners();
  }

  void clearHistory() {
    cancelCheck();
    results.clear();
    startedAt = null;
    message = null;
    notifyListeners();
  }

  Future<void> check(
    SavedCommute trip,
    List<SavedGate> favorites, {
    DateTime? pausedUntil,
    DateTime? lastNearbyCheck,
  }) async {
    if (_disposed ||
        checking != null ||
        !trips.any((row) => row.id == trip.id)) {
      return;
    }
    final own = startedAt;
    final previous = own == null || (lastNearbyCheck?.isAfter(own) ?? false)
        ? lastNearbyCheck
        : own;
    final now = DateTime.now();
    if (pausedUntil?.isAfter(now) == true ||
        previous != null &&
            now.difference(previous) < const Duration(seconds: 90)) {
      message = pausedUntil?.isAfter(now) == true
          ? "Checks are paused. Try again after the service pause."
          : "Checked recently. Wait 90 seconds between manual train checks.";
      notifyListeners();
      return;
    }

    final byId = {for (final item in favorites) item.gate.id: item};
    final gates = [
      for (final id in trip.gateIds)
        if (byId[id] case final SavedGate item) item,
    ];
    if (gates.isEmpty) return;
    final abort = Completer<void>();
    _abort = abort;
    final checked = results.putIfAbsent(trip.id, () => {});
    DateTime? retryAt;
    checking = trip.id;
    message = null;
    startedAt = now;
    notifyListeners();

    bool current() => !_disposed && identical(_abort, abort);
    Future<CommuteGateCheck> read(SavedGate item) async {
      final id = item.gate.id;
      CommuteGateCheck failure(String reason, [String? canonical]) {
        final key = canonical ?? id;
        return (checked[key] ?? checked[id])
                ?.forGate(key)
                .afterFailure(reason) ??
            CommuteGateCheck(key, error: reason);
      }

      try {
        final service = api;
        final scene = await (service is CommuteSceneApi
            ? (service as CommuteSceneApi).commuteScene(
                item.place.lat,
                item.place.lon,
                id,
                abort.future,
              )
            : service.scene(item.place.lat, item.place.lon, id));
        final crossing = scene.crossing;
        if (crossing == null ||
            !sceneIdentityMatches(
              id,
              crossing.id,
              aliasResolved: scene.legacyAliasResolved,
            )) {
          return failure(
            scene.error.isEmpty
                ? "Crossing check unavailable"
                : friendlyError(scene.error),
          );
        }
        if (current() && crossing.id != id && !scene.offline) {
          onAlias?.call(item, crossing);
        }
        if (scene.error.isNotEmpty || !scene.available) {
          return failure("Crossing check unavailable", crossing.id);
        }
        if (scene.incomplete &&
            scene.trains.isEmpty &&
            checked[crossing.id]?.scene != null) {
          return failure("The latest check was incomplete.", crossing.id);
        }
        return CommuteGateCheck(
          crossing.id,
          scene: scene,
          at: scene.savedAt ?? DateTime.now(),
        );
      } on RailException catch (error) {
        final pause = error.retryAt;
        if (pause != null && (retryAt == null || pause.isAfter(retryAt!))) {
          retryAt = pause;
          if (current()) _onPause(pause);
        }
        return failure(
          pause == null
              ? "Could not check this crossing"
              : "Check paused · try again later",
        );
      } catch (_) {
        return failure("Could not check this crossing");
      }
    }

    try {
      for (var i = 0; i < gates.length && retryAt == null; i += 2) {
        final rows = await Future.wait(gates.skip(i).take(2).map(read));
        if (!current()) return;
        final tripNow = trips.where((row) => row.id == trip.id).firstOrNull;
        if (tripNow == null) return;
        for (final row in rows) {
          if (tripNow.gateIds.contains(row.gateId)) checked[row.gateId] = row;
        }
        notifyListeners();
      }
      if (retryAt != null && current()) {
        message = "Checks are paused. Try again after the service pause.";
      }
    } finally {
      if (current()) {
        _abort = null;
        checking = null;
        abort.complete();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _abort?.complete();
    _abort = null;
    super.dispose();
  }
}
