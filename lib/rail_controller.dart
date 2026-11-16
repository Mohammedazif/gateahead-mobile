import "dart:async";

import "package:flutter/foundation.dart";

import "api.dart";
import "format.dart";
import "models.dart";
import "device_store.dart";
import "timing.dart";

class RailController extends ChangeNotifier {
  RailController(
    this.api, {
    this.nameDelay = const Duration(milliseconds: 280),
    this.storage,
  }) {
    favorites = storage?.favorites() ?? [];
    refresh = storage?.settings() ?? const RefreshSettings();
    pausedUntil = storedDateTime(storage?.read("paused-until"));
  }

  final DeviceStore? storage;
  late List<SavedGate> favorites;
  late RefreshSettings refresh;
  DateTime? lastAttempt;
  DateTime? pausedUntil;
  bool gatesCached = false;
  bool get historical =>
      predict?.offline == true ||
      (checkedAt != null &&
          DateTime.now().difference(checkedAt!).inMinutes >= 5);
  bool get paused =>
      pausedUntil != null && DateTime.now().isBefore(pausedUntil!);
  bool get sceneHistorical =>
      scene?.offline == true ||
      (scene?.savedAt != null &&
          DateTime.now().difference(scene!.savedAt!).inMinutes >= 5);

  final Duration nameDelay;

  final RailApi api;

  Spot? place;
  String? placeLabel;
  Spot? pending;
  String? spotName;
  bool naming = false;
  List<Gate> gates = const [];
  bool loadingGates = false;
  String? gatesNote;
  Predict? _predict;
  final Map<String, Scene> _gateChecks = {};
  List<Scene> get gateChecks {
    final now = DateTime.now();
    final predictionAt = _predict?.savedAt ?? _predict?.generatedAt;
    return [
      for (final check in _gateChecks.values)
        if (!check.offline &&
            check.savedAt != null &&
            (predictionAt == null || !check.savedAt!.isBefore(predictionAt)) &&
            now.difference(check.savedAt!).inMinutes < 5)
          currentScene(check, now)!,
    ];
  }

  Predict? get predict => withGateChecks(
    currentPrediction(_predict, DateTime.now()),
    gateChecks,
    gates,
  );
  set predict(Predict? value) => _predict = value;
  List<Gate> get markedGates =>
      markGates(gates, historical ? null : predict, gateChecks);
  DateTime? checkedAt;
  bool checking = false;
  bool locating = false;
  String? error;
  Gate? selected;
  Scene? _scene;
  Scene? get scene => currentScene(_scene, DateTime.now());
  set scene(Scene? value) => _scene = value;
  bool sceneLoading = false;
  String? sceneMessage;

  int _generation = 0;
  int _sceneTicket = 0;
  int _locationTicket = 0;
  bool _confirming = false;
  Timer? _nameTimer;

  void askPlace(double lat, double lon) {
    _locationTicket++;
    locating = false;
    pending = Spot(lat, lon);
    spotName = null;
    naming = true;
    notifyListeners();
    _nameTimer?.cancel();
    final asked = pending;
    _nameTimer = Timer(nameDelay, () async {
      try {
        final name = await api.placeName(lat, lon);
        if (!identical(pending, asked)) return;
        spotName = name?.trim();
        if (spotName?.isEmpty ?? false) spotName = null;
      } catch (_) {
        if (!identical(pending, asked)) return;
        spotName = null;
      } finally {
        if (identical(pending, asked)) {
          naming = false;
          notifyListeners();
        }
      }
    });
  }

  void cancelPending() {
    _nameTimer?.cancel();
    pending = null;
    spotName = null;
    naming = false;
    notifyListeners();
  }

  Future<void> confirmPlace() async {
    final next = pending;
    if (next == null || _confirming) return;
    _confirming = true;
    _nameTimer?.cancel();
    final label = spotName;
    try {
      await choosePlace(next.lat, next.lon, label: label);
    } finally {
      _confirming = false;
    }
  }

  Future<void> choosePlace(double lat, double lon, {String? label}) async {
    final ticket = ++_generation;
    _sceneTicket += 1;
    _gateChecks.clear();
    _nameTimer?.cancel();
    final knownLabel = label?.trim();
    final hasLabel = knownLabel != null && knownLabel.isNotEmpty;
    place = Spot(lat, lon);
    placeLabel = hasLabel ? knownLabel : formatSpot(lat, lon);
    pending = null;
    spotName = null;
    naming = false;
    final oldPredict = storage?.response(responseKey("/predict", lat, lon));
    predict = oldPredict == null ? null : Predict.parse(oldPredict.restored());
    checkedAt = oldPredict?.at;
    final oldGates = storage?.response(responseKey("/gates", lat, lon));
    gates = oldGates == null ? const [] : GatesBody.parse(oldGates.data).gates;
    gatesCached = oldGates != null;
    lastAttempt = null;
    unawaited(
      storage
              ?.write("last-place", {
                "lat": lat,
                "lon": lon,
                "label": placeLabel,
              })
              .then<void>((_) {}) ??
          Future<void>.value(),
    );
    error = null;
    selected = null;
    scene = null;
    sceneLoading = false;
    sceneMessage = null;
    locating = false;
    checking = false;
    loadingGates = true;
    gatesNote = null;
    notifyListeners();
    if (!hasLabel) unawaited(_resolvePlaceLabel(lat, lon, ticket));
    try {
      final body = await api.gates(lat, lon);
      if (ticket != _generation) return;
      if (body.error.isEmpty) gates = body.gates;
      gatesCached = body.offline;
      gatesNote = body.error.isEmpty ? null : friendlyError(body.error);
    } on RailException catch (err) {
      if (ticket != _generation) return;
      if (oldGates == null) gates = const [];
      gatesNote = err.message;
    } catch (_) {
      if (ticket != _generation) return;
      if (oldGates == null) gates = const [];
      gatesNote = "Could not load crossings.";
    } finally {
      if (ticket == _generation) {
        loadingGates = false;
        notifyListeners();
      }
    }
  }

  Future<void> _resolvePlaceLabel(double lat, double lon, int ticket) async {
    try {
      final name = (await api.placeName(lat, lon))?.trim();
      if (ticket != _generation || name == null || name.isEmpty) return;
      placeLabel = name;
      notifyListeners();
    } catch (_) {
      // Keep the coordinates when the place name is unavailable.
    }
  }

  void failLocation() {
    locating = false;
    error = "Location was blocked. Tap the map to drop a pin.";
    notifyListeners();
  }

  void openCity(String label, double lat, double lon) {
    unawaited(choosePlace(lat, lon, label: label));
  }

  void beginLocate() {
    _locationTicket++;
    locating = true;
    error = null;
    notifyListeners();
  }

  Future<void> locate(Future<Spot> Function() readPosition) async {
    beginLocate();
    final ticket = _locationTicket, generation = _generation;
    bool current() => ticket == _locationTicket && generation == _generation;
    try {
      final position = await readPosition();
      if (current()) await choosePlace(position.lat, position.lon);
    } catch (_) {
      if (current()) failLocation();
    }
  }

  Future<void> check({bool automatic = false}) async {
    final here = place;
    if (here == null || checking) return;
    if (paused) {
      if (!automatic) {
        error = "Checks are paused until ${pausedUntil!.toLocal()}.";
        notifyListeners();
      }
      return;
    }
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt!).inSeconds < 90) {
      if (!automatic) {
        error = "Checked recently. Wait 90 seconds between train checks.";
        notifyListeners();
      }
      return;
    }
    lastAttempt = DateTime.now();
    final ticket = _generation;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final body = await api.predict(here.lat, here.lon);
      if (ticket != _generation) return;
      if (body.error.isNotEmpty) throw RailException(friendlyError(body.error));
      predict = body;
      checkedAt = body.savedAt ?? DateTime.now();
      if (selected != null && !body.offline) {
        unawaited(openGate(selected!, refreshing: true));
      }
    } on RailException catch (err) {
      if (ticket != _generation) return;
      error = err.message;
      if (err.retryAt != null) {
        pausedUntil = err.retryAt;
        unawaited(
          storage
                  ?.write("paused-until", pausedUntil!.millisecondsSinceEpoch)
                  .then<void>((_) {}) ??
              Future<void>.value(),
        );
      }
    } catch (_) {
      if (ticket != _generation) return;
      error = "Could not check trains.";
    } finally {
      if (ticket == _generation) {
        checking = false;
        notifyListeners();
      }
    }
  }

  Future<void> openGate(Gate gate, {bool refreshing = false}) async {
    final here = place;
    if (here == null) return;
    final ticket = ++_sceneTicket;
    selected = gate;
    sceneLoading = !refreshing;
    if (!refreshing) scene = null;
    sceneMessage = null;
    notifyListeners();
    try {
      final body = await api.scene(here.lat, here.lon, gate.id);
      if (ticket != _sceneTicket) return;
      scene = body;
      if (body.available &&
          !body.offline &&
          body.error.isEmpty &&
          body.crossing?.id == gate.id) {
        _gateChecks[gate.id] = body;
      }
      if (!body.available || body.rail.length < 2) {
        sceneMessage = body.error.isNotEmpty ? friendlyError(body.error) : "This crossing has no rail line on the map, so the train stays off it.";
      }
    } on RailException catch (err) {
      if (ticket != _sceneTicket) return;
      sceneMessage = err.message;
      if (err.retryAt != null) {
        pausedUntil = err.retryAt;
        unawaited(
          storage
                  ?.write("paused-until", pausedUntil!.millisecondsSinceEpoch)
                  .then<void>((_) {}) ??
              Future<void>.value(),
        );
      }
    } catch (_) {
      if (ticket != _sceneTicket) return;
      sceneMessage = "Could not open this crossing.";
    } finally {
      if (ticket == _sceneTicket) {
        sceneLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> restore() async {
    final row = storage?.read("last-place");
    if (row is Map && validCoordinates(row["lat"], row["lon"])) {
      await choosePlace(
        (row["lat"] as num).toDouble(),
        (row["lon"] as num).toDouble(),
        label: row["label"] is String ? row["label"] : null,
      );
    }
  }

  void setRefresh(RefreshSettings value) {
    refresh = value;
    unawaited(
      storage?.write("refresh", value.toJson()).then<void>((_) {}) ??
          Future<void>.value(),
    );
    notifyListeners();
  }

  Future<void> autoCheck({required bool visible}) async {
    notifyListeners();
    if (!visible ||
        !refresh.enabled ||
        !refresh.allows(DateTime.now()) ||
        paused) {
      return;
    }
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt!).inSeconds < 120) {
      return;
    }
    await check(automatic: true);
  }

  bool isSaved(Gate gate) => favorites.any((item) => item.gate.id == gate.id);

  void saveGate(Gate gate, String label) {
    if (place == null || label.trim().isEmpty) return;
    favorites = [
      ...favorites.where((item) => item.gate.id != gate.id),
      SavedGate(gate, label.trim(), place!),
    ];
    if (favorites.length > 50) favorites.removeAt(0);
    _saveFavorites();
  }

  void removeSaved(String id) {
    favorites = favorites.where((item) => item.gate.id != id).toList();
    _saveFavorites();
  }

  void renameSaved(SavedGate item, String label) {
    if (label.trim().isEmpty) return;
    favorites = favorites
        .map(
          (row) => row.gate.id == item.gate.id
              ? SavedGate(row.gate, label.trim(), row.place)
              : row,
        )
        .toList();
    _saveFavorites();
  }

  void _saveFavorites() {
    unawaited(
      storage
              ?.write(
                "favorites",
                favorites.map((item) => item.toJson()).toList(),
              )
              .then<void>((_) {}) ??
          Future<void>.value(),
    );
    notifyListeners();
  }

  Future<void> openSaved(SavedGate saved) async {
    final ticket = _generation + 1;
    final sceneTicket = _sceneTicket + 1;
    await choosePlace(saved.place.lat, saved.place.lon, label: saved.label);
    if (ticket != _generation || sceneTicket != _sceneTicket) return;
    final match = gates.where((gate) => gate.id == saved.gate.id).firstOrNull;
    await openGate(match ?? saved.gate);
  }

  Future<bool> openLink(String text) async {
    final link = parseCrossingLink(text);
    if (link == null) return false;
    final ticket = _generation + 1;
    final sceneTicket = _sceneTicket + 1;
    await choosePlace(link.place.lat, link.place.lon);
    if (ticket != _generation || sceneTicket != _sceneTicket) return true;
    final gate = gates.where((gate) => gate.id == link.gateId).firstOrNull;
    if (gate != null) await openGate(gate);
    return true;
  }

  void closeScene() {
    _sceneTicket += 1;
    selected = null;
    scene = null;
    sceneLoading = false;
    sceneMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation += 1;
    _sceneTicket += 1;
    pending = null;
    _nameTimer?.cancel();
    super.dispose();
  }
}
