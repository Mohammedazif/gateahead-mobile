import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/device_store.dart";
import "package:gateahead/format.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("offline predictions retain their original check time", () async {
    final store = DeviceStore(await SharedPreferences.getInstance());
    var offline = false;
    final client = MockClient((request) async {
      if (offline) throw Exception("offline");
      return http.Response(
        jsonEncode({"crossings": 1, "approaching": [], "sightings": []}),
        200,
      );
    });
    final api = HttpRailApi(
      base: "https://example.test",
      client: client,
      storage: store,
    );
    final fresh = await api.predict(12, 75);
    offline = true;
    final restored = await api.predict(12, 75);
    expect(fresh.offline, isFalse);
    expect(restored.offline, isTrue);
    expect(restored.savedAt, fresh.savedAt);
    expect(restored.crossings, 1);
  });

  test(
    "saved gate names survive a new controller and can be removed",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      final api = _Api();
      final first = RailController(api, storage: store);
      await first.choosePlace(12, 75, label: "Kannur");
      const gate = Gate(
        id: "osm:1",
        name: "LC",
        lat: 12,
        lon: 75,
        km: 0,
        source: "osm",
      );
      first.saveGate(gate, "Home");
      await Future<void>.delayed(Duration.zero);
      final second = RailController(api, storage: store);
      expect(second.favorites.single.label, "Home");
      second.renameSaved(second.favorites.single, "Office");
      expect(second.favorites.single.label, "Office");
      second.removeSaved(gate.id);
      expect(second.favorites, isEmpty);
      first.dispose();
      second.dispose();
    },
  );

  test(
    "automatic checks pause in the background and respect the interval",
    () async {
      final api = _Api();
      final rail = RailController(api);
      await rail.choosePlace(12, 75, label: "Kannur");
      rail.setRefresh(const RefreshSettings(enabled: true));
      await rail.autoCheck(visible: false);
      expect(api.checks, 0);
      await rail.autoCheck(visible: true);
      await rail.autoCheck(visible: true);
      expect(api.checks, 1);
      rail.dispose();
    },
  );

  test(
    "weekday overnight commute includes early Saturday but not early Monday",
    () {
      const settings = RefreshSettings(
        commute: true,
        start: "22:00",
        end: "02:00",
      );
      expect(settings.allows(DateTime(2026, 11, 21, 1)), isTrue);
      expect(settings.allows(DateTime(2026, 11, 23, 1)), isFalse);
      expect(settings.allows(DateTime(2026, 11, 20, 12)), isFalse);
    },
  );

  test("crossing links round trip and reject invalid coordinates", () {
    const gate = Gate(
      id: "osm:1",
      name: "Home gate",
      lat: 12.1,
      lon: 75.2,
      km: 0,
      source: "osm",
    );
    final parsed = parseCrossingLink(crossingLink(gate));
    expect(parsed?.place, gate.spot);
    expect(parsed?.gateId, gate.id);
    expect(
      parseCrossingLink("https://gateahead.vercel.app/?lat=NaN&lon=75"),
      isNull,
    );
    expect(
      parseCrossingLink("https://gateahead.vercel.app/?lat=91&lon=75"),
      isNull,
    );
  });

  test("a passed gate does not inherit its cluster's closed status", () {
    final gates = [
      for (final id in ["passed", "next"])
        Gate(id: id, name: "Road $id", lat: 12, lon: 75, km: 0, source: "osm"),
    ];
    final predict = Predict.parse({
      "approaching": [
        {
          "train": "16323",
          "eta": 0,
          "status": "closed",
          "ids": ["passed", "next"],
        },
      ],
      "gate_predictions": [
        {"id": "next", "eta": 3, "status": "closed", "closes_in": -2},
      ],
    });
    final marked = markGates(gates, predict);
    expect(marked.first.status, isNull);
    expect(marked.last.eta, 3);
    expect(marked.last.name, "Road next");
  });

  test("a newer prediction forces a fresh crossing detail request", () async {
    final store = DeviceStore(await SharedPreferences.getInstance());
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.write("responses", {
      "/scene?lat=12.0&lon=75.0&crossing_id=osm%3A1": {
        "at": now - 1000,
        "data": {"available": true, "trains": []},
      },
      "/predict?lat=12.0&lon=75.0": {
        "at": now,
        "data": {"approaching": []},
      },
    });
    var calls = 0;
    final api = HttpRailApi(
      base: "https://example.test",
      storage: store,
      client: MockClient((request) async {
        calls++;
        return http.Response('{"available":true,"trains":[]}', 200);
      }),
    );
    await api.scene(12, 75, "osm:1");
    expect(calls, 1);
  });
}

class _Api implements RailApi {
  int checks = 0;
  @override
  Future<List<CityHit>> cities(String query) async => [];
  @override
  Future<String?> placeName(double lat, double lon) async => null;
  @override
  Future<GatesBody> gates(double lat, double lon) async =>
      const GatesBody(gates: []);
  @override
  Future<Predict> predict(double lat, double lon) async {
    checks++;
    return const Predict();
  }

  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async =>
      const Scene(available: false);
}
