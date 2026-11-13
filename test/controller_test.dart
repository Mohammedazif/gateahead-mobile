import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/format.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";

void main() {
  test("a newer place wins when two lookups overlap", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    final first = rail.choosePlace(12, 75);
    final second = rail.choosePlace(13, 76);
    api.placeCompleters[1].complete("Kozhikode");
    api.placeCompleters[0].complete("Kannur");
    api.gatesCompleters[1].complete(
      const GatesBody(
        gates: [
          Gate(
            id: "new",
            name: "New",
            lat: 13,
            lon: 76,
            km: 0.2,
            source: "osm",
          ),
        ],
      ),
    );
    api.gatesCompleters[0].complete(
      const GatesBody(
        gates: [
          Gate(id: "old", name: "Old", lat: 12, lon: 75, km: 1, source: "osm"),
        ],
      ),
    );
    await Future.wait([first, second]);
    expect(rail.gates.single.id, "new");
    expect(rail.placeLabel, "Kozhikode");
    expect(rail.loadingGates, isFalse);
    rail.dispose();
  });

  test("the place name waits, then a confirm loads gates", () async {
    final api = _ScriptedApi();
    final rail = RailController(
      api,
      nameDelay: const Duration(milliseconds: 20),
    );
    rail.askPlace(12.25, 75.1);
    expect(rail.naming, isTrue);
    expect(api.placeCalls, 0);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(api.placeCalls, 1);
    api.placeCompleters.single.complete("Payyanur");
    await Future<void>.delayed(Duration.zero);
    expect(rail.spotName, "Payyanur");

    final confirmed = rail.confirmPlace();
    expect(rail.pending, isNull);
    expect(rail.loadingGates, isTrue);
    api.gatesCompleters.single.complete(const GatesBody(gates: []));
    await confirmed;
    expect(rail.place, const Spot(12.25, 75.1));
    expect(rail.placeLabel, "Payyanur");
    expect(api.placeCalls, 1);
    expect(rail.gates, isEmpty);
    expect(rail.loadingGates, isFalse);
    rail.dispose();
  });

  test("GPS loads crossings while its place name is still pending", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    addTearDown(rail.dispose);
    final placed = rail.choosePlace(12, 75);
    api.gatesCompleters.single.complete(const GatesBody(gates: []));
    await placed;
    expect(rail.loadingGates, isFalse);
    expect(rail.placeLabel, formatSpot(12, 75));

    api.placeCompleters.single.complete("  Kannur  ");
    await Future<void>.delayed(Duration.zero);
    expect(rail.placeLabel, "Kannur");
  });

  test(
    "confirming before the preview resolves still names the place",
    () async {
      final api = _ScriptedApi();
      final rail = RailController(api, nameDelay: const Duration(seconds: 1));
      addTearDown(rail.dispose);
      rail.askPlace(12, 75);
      final confirmed = rail.confirmPlace();
      expect(api.placeCalls, 1);
      expect(rail.naming, isFalse);
      api.gatesCompleters.single.complete(const GatesBody(gates: []));
      await confirmed;
      api.placeCompleters.single.complete("Payyanur");
      await Future<void>.delayed(Duration.zero);
      expect(rail.placeLabel, "Payyanur");
    },
  );

  test("missing or failed names retain coordinates and crossings", () async {
    for (final reply in [null, "  ", Exception("offline")]) {
      final api = _ScriptedApi();
      final rail = RailController(api);
      final placed = rail.choosePlace(12, 75);
      if (reply is Exception) {
        api.placeCompleters.single.completeError(reply);
      } else {
        api.placeCompleters.single.complete(reply as String?);
      }
      api.gatesCompleters.single.complete(const GatesBody(gates: []));
      await placed;
      expect(rail.placeLabel, formatSpot(12, 75));
      expect(rail.gatesNote, isNull);
      expect(rail.loadingGates, isFalse);
      rail.dispose();
    }
  });

  test("cancelled map picks and blocked GPS retain the chosen city", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    addTearDown(rail.dispose);
    rail.openCity("Kannur, Kerala", 12, 75);
    api.gatesCompleters.single.complete(const GatesBody(gates: []));
    await Future<void>.delayed(Duration.zero);
    rail.askPlace(13, 76);
    rail.cancelPending();
    expect(rail.placeLabel, "Kannur, Kerala");
    rail.beginLocate();
    rail.failLocation();
    expect(rail.placeLabel, "Kannur, Kerala");
    expect(api.placeCalls, 0);
  });

  test("an old GPS name cannot replace a newly chosen city", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    addTearDown(rail.dispose);
    final placed = rail.choosePlace(12, 75);
    rail.openCity("Pune, Maharashtra", 18.52, 73.86);
    api.gatesCompleters[0].complete(const GatesBody(gates: []));
    api.gatesCompleters[1].complete(const GatesBody(gates: []));
    api.placeCompleters.single.complete("Kannur");
    await placed;
    await Future<void>.delayed(Duration.zero);
    expect(rail.placeLabel, "Pune, Maharashtra");
    expect(api.placeCalls, 1);
  });

  test("disposing ignores outstanding name and crossing lookups", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    final placed = rail.choosePlace(12, 75);
    rail.dispose();
    api.placeCompleters.single.complete("Kannur");
    api.gatesCompleters.single.complete(const GatesBody(gates: []));
    await placed;
    expect(rail.placeLabel, formatSpot(12, 75));
  });

  test("an open crossing ignores a late scene after close", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    final placed = rail.choosePlace(12, 75);
    api.gatesCompleters.single.complete(const GatesBody(gates: []));
    await placed;
    const gate = Gate(
      id: "n1",
      name: "LC",
      lat: 12,
      lon: 75,
      km: 0.3,
      source: "osm",
    );
    final opening = rail.openGate(gate);
    rail.closeScene();
    api.sceneCompleter.complete(
      const Scene(available: true, rail: [Spot(12, 75), Spot(12.01, 75)]),
    );
    await opening;
    expect(rail.selected, isNull);
    expect(rail.scene, isNull);
    rail.dispose();
  });
}

class _ScriptedApi implements RailApi {
  final placeCompleters = <Completer<String?>>[];
  final gatesCompleters = <Completer<GatesBody>>[];
  final sceneCompleter = Completer<Scene>();
  var placeCalls = 0;

  @override
  Future<List<CityHit>> cities(String query) async => const [];

  @override
  Future<String?> placeName(double lat, double lon) {
    placeCalls += 1;
    final next = Completer<String?>();
    placeCompleters.add(next);
    return next.future;
  }

  @override
  Future<GatesBody> gates(double lat, double lon) {
    final next = Completer<GatesBody>();
    gatesCompleters.add(next);
    return next.future;
  }

  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();

  @override
  Future<Scene> scene(double lat, double lon, String crossingId) =>
      sceneCompleter.future;
}
