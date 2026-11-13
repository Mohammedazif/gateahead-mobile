import "dart:async";

import "package:flutter/foundation.dart";

import "api.dart";
import "format.dart";
import "models.dart";

class RailController extends ChangeNotifier {
  RailController(
    this.api, {
    this.nameDelay = const Duration(milliseconds: 280),
  });

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
  Predict? predict;
  DateTime? checkedAt;
  bool checking = false;
  bool locating = false;
  String? error;
  Gate? selected;
  Scene? scene;
  bool sceneLoading = false;
  String? sceneMessage;

  int _generation = 0;
  int _sceneTicket = 0;
  bool _confirming = false;
  Timer? _nameTimer;

  void askPlace(double lat, double lon) {
    pending = Spot(lat, lon);
    spotName = null;
    naming = true;
    notifyListeners();
    _nameTimer?.cancel();
    final asked = pending;
    _nameTimer = Timer(nameDelay, () async {
      try {
        final name = await api.placeName(lat, lon);
        if (pending != asked) return;
        spotName = name?.trim();
        if (spotName?.isEmpty ?? false) spotName = null;
      } catch (_) {
        if (pending != asked) return;
        spotName = null;
      } finally {
        if (pending == asked) {
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
    _nameTimer?.cancel();
    final knownLabel = label?.trim();
    final hasLabel = knownLabel != null && knownLabel.isNotEmpty;
    place = Spot(lat, lon);
    placeLabel = hasLabel ? knownLabel : formatSpot(lat, lon);
    pending = null;
    spotName = null;
    naming = false;
    predict = null;
    checkedAt = null;
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
      gates = body.gates;
      gatesNote = body.error.isEmpty ? null : friendlyError(body.error);
    } on RailException catch (err) {
      if (ticket != _generation) return;
      gates = const [];
      gatesNote = err.message;
    } catch (_) {
      if (ticket != _generation) return;
      gates = const [];
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
    locating = true;
    error = null;
    notifyListeners();
  }

  Future<void> check() async {
    final here = place;
    if (here == null || checking) return;
    final ticket = _generation;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final body = await api.predict(here.lat, here.lon);
      if (ticket != _generation) return;
      predict = body;
      checkedAt = DateTime.now();
    } on RailException catch (err) {
      if (ticket != _generation) return;
      error = err.message;
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

  Future<void> openGate(Gate gate) async {
    final here = place;
    if (here == null) return;
    final ticket = ++_sceneTicket;
    selected = gate;
    sceneLoading = true;
    scene = null;
    sceneMessage = null;
    notifyListeners();
    try {
      final body = await api.scene(here.lat, here.lon, gate.id);
      if (ticket != _sceneTicket) return;
      scene = body;
      if (!body.available || body.rail.length < 2) {
        sceneMessage = body.error.isNotEmpty ? friendlyError(body.error) : "This crossing has no rail line on the map, so the train stays off it.";
      }
    } on RailException catch (err) {
      if (ticket != _sceneTicket) return;
      sceneMessage = err.message;
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
