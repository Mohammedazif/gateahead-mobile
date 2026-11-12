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
    placeLabel = null;
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
        spotName = name;
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
    placeLabel = null;
    pending = null;
    notifyListeners();
    try {
      await choosePlace(next.lat, next.lon);
    } finally {
      _confirming = false;
    }
  }

  Future<void> choosePlace(double lat, double lon) async {
    final ticket = ++_generation;
    _sceneTicket += 1;
    place = Spot(lat, lon);
    pending = null;
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

  void failLocation() {
    locating = false;
    error = "Location was blocked. Tap the map to drop a pin.";
    notifyListeners();
  }

  void openCity(String label, double lat, double lon) {
    placeLabel = label;
    unawaited(choosePlace(lat, lon));
  }

  void beginLocate() {
    placeLabel = null;
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
    _nameTimer?.cancel();
    super.dispose();
  }
}
