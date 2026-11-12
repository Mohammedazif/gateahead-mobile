import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";

void main() {
  test("a newer place wins when two lookups overlap", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    final first = rail.choosePlace(12, 75);
    final second = rail.choosePlace(13, 76);
    api.gatesCompleters[1].complete(
      const GatesBody(gates: [Gate(id: "new", name: "New", lat: 13, lon: 76, km: 0.2, source: "osm")]),
    );
    api.gatesCompleters[0].complete(
      const GatesBody(gates: [Gate(id: "old", name: "Old", lat: 12, lon: 75, km: 1, source: "osm")]),
    );
    await Future.wait([first, second]);
    expect(rail.gates.single.id, "new");
    expect(rail.loadingGates, isFalse);
    rail.dispose();
  });

  test("the place name waits, then a confirm loads gates", () async {
    final api = _ScriptedApi();
    final rail = RailController(api, nameDelay: const Duration(milliseconds: 20));
    rail.askPlace(12.25, 75.1);
    expect(rail.naming, isTrue);
    expect(api.placeCalls, 0);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(api.placeCalls, 1);
    api.placeCompleter.complete("Payyanur");
    await Future<void>.delayed(Duration.zero);
    expect(rail.spotName, "Payyanur");

    final confirmed = rail.confirmPlace();
    expect(rail.pending, isNull);
    expect(rail.loadingGates, isTrue);
    api.gatesCompleters.single.complete(const GatesBody(gates: []));
    await confirmed;
    expect(rail.place, const Spot(12.25, 75.1));
    expect(rail.gates, isEmpty);
    expect(rail.loadingGates, isFalse);
    rail.dispose();
  });

  test("an open crossing ignores a late scene after close", () async {
    final api = _ScriptedApi();
    final rail = RailController(api);
    final placed = rail.choosePlace(12, 75);
    api.gatesCompleters.single.complete(const GatesBody(gates: []));
    await placed;
    const gate = Gate(id: "n1", name: "LC", lat: 12, lon: 75, km: 0.3, source: "osm");
    final opening = rail.openGate(gate);
    rail.closeScene();
    api.sceneCompleter.complete(const Scene(available: true, rail: [Spot(12, 75), Spot(12.01, 75)]));
    await opening;
    expect(rail.selected, isNull);
    expect(rail.scene, isNull);
    rail.dispose();
  });
}

class _ScriptedApi implements RailApi {
  final placeCompleter = Completer<String?>();
  final gatesCompleters = <Completer<GatesBody>>[];
  final sceneCompleter = Completer<Scene>();
  var placeCalls = 0;

  @override
  Future<String?> placeName(double lat, double lon) {
    placeCalls += 1;
    return placeCompleter.future;
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
  Future<Scene> scene(double lat, double lon, String crossingId) => sceneCompleter.future;
}
