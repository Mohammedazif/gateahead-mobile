import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/device_store.dart";
import "package:gateahead/format.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/timing.dart";
import "package:gateahead/ui/train_sheet.dart";
import "package:google_fonts/google_fonts.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:shared_preferences/shared_preferences.dart";

const _gate = Gate(
  id: "A",
  name: "School Road",
  lat: 12,
  lon: 75,
  km: .4,
  source: "osm",
);
const _crossing = SceneCrossing(id: "A", name: "School Road", lat: 12, lon: 75);
const _trainNumber = "16512";
const _date = "2026-11-16";
const _identity = "$_trainNumber:$_date";
const _legacyId = "user:123456:1000";
const _currentId = "pin:1234567890ab4cde8f0123456789abcd";

const _arrival = SceneTrain(
  number: _trainNumber,
  startDate: _date,
  name: "Sample train",
  etaMin: 2,
  status: "closed",
  alongKm: .4,
  ageMin: 1,
  closesInMin: -3,
  observed: true,
  movement: "moving",
  positionOnSegment: true,
);
const _estimate = GatePrediction(
  id: "A",
  train: _trainNumber,
  startDate: _date,
  eta: 2,
  closesIn: -3,
  status: "closed",
);

Map<String, Object?> _response(
  String id, {
  List<Map<String, Object?>> trains = const [],
  bool alias = false,
  bool available = true,
}) => {
  "available": available,
  "crossing": {"id": id, "lat": 12, "lon": 75},
  "rail": [
    if (available) ...[
      [12, 75],
      [12.01, 75],
    ],
  ],
  if (!available) "error": "map_unavailable",
  "trains": trains,
  if (alias) "legacy_alias_resolved": true,
};

const _wireTrain = {
  "number": _trainNumber,
  "eta_min": 2,
  "status": "closed",
  "along_km": .4,
  "age_min": 1,
};
const _sceneKey = "/scene?lat=12.0&lon=75.0&crossing_id=A";
const _gatesKey = "/gates?lat=12.0&lon=75.0";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test("a partial empty scene retains a prior estimate and advertises incomplete coverage", () {
    final previous = Predict(
      savedAt: DateTime.utc(2026, 11, 16),
      gatePredictions: [_estimate],
    );
    final at = previous.savedAt!.add(const Duration(seconds: 30));
    final partial = Scene(
      available: true,
      crossing: _crossing,
      savedAt: at,
      coverage: const TrainCoverage(status: "partial"),
    );
    final partialResult = withGateChecks(previous, [partial], [_gate])!;
    expect(partialResult.gatePredictions!.single.eta, _estimate.eta);
    expect(partialResult.gatePredictions!.single.earlierEstimate, isTrue);
    expect(partialResult.coverage!.notice, contains("incomplete"));

    final complete = Scene(available: true, crossing: _crossing, savedAt: at);
    expect(
      withGateChecks(previous, [complete], [_gate])!.gatePredictions,
      isEmpty,
    );
  });

  test("stopped and moving evidence stay independent at the same crossing", () {
    final snapshot = Predict(
      gatePredictions: const [_estimate],
      awaitingUpdate: const [
        AwaitingTrain(
          number: "16603",
          name: "",
          current: "",
          ageMin: 8,
          reason: "stale_report",
          ids: ["A"],
        ),
      ],
    );
    final result = markGates([_gate], snapshot).single;
    expect(result.status, "closed");
    expect(result.eta, 2);
    expect(result.hasUncertainTrain, isTrue);
  });

  test(
    "the latest dated run evidence wins regardless of selected gate order",
    () {
      final now = DateTime.utc(2026, 11, 16);
      final resumed = Scene(
        available: true,
        savedAt: now,
        crossing: _crossing,
        trains: const [_arrival],
      );
      final cancelled = Scene(
        available: true,
        savedAt: now.subtract(const Duration(seconds: 30)),
        crossing: const SceneCrossing(id: "B", name: "", lat: 12, lon: 75),
        serviceUpdates: const [
          ServiceUpdate(
            number: _trainNumber,
            startDate: _date,
            status: "cancelled",
          ),
        ],
      );
      for (final checks in [
        [resumed, cancelled],
        [cancelled, resumed],
      ]) {
        final result = withGateChecks(
          const Predict(gatePredictions: []),
          checks,
          [_gate],
        )!;
        expect(result.serviceUpdates, isEmpty);
        expect(result.gatePredictions!.single.identity, _identity);
      }
    },
  );

  test(
    "map markers filter each dated train and stale motion becomes unresolved",
    () {
      final now = DateTime.utc(2026, 11, 16);
      const expired = SceneTrain(
        number: "16603",
        name: "",
        etaMin: 3,
        status: "closed",
        alongKm: 0,
        ageMin: 7,
        positionOnSegment: true,
        observed: true,
        movement: "moving",
      );
      const unplaced = SceneTrain(
        number: "16604",
        name: "",
        etaMin: 4,
        status: "closed",
        alongKm: 0,
        ageMin: 1,
      );
      const scheduled = SceneTrain(
        number: "16605",
        name: "",
        etaMin: 5,
        status: "approaching",
        alongKm: 0,
        ageMin: 0,
        positionOnSegment: true,
        observed: false,
      );
      final scene = Scene(
        available: true,
        crossing: _crossing,
        savedAt: now,
        rail: const [Spot(12, 75), Spot(12.01, 75)],
        trains: const [unplaced, expired, _arrival, scheduled],
      );
      expect(
        sceneTrainPositions(scene, now).keys,
        unorderedEquals(["16603", _identity]),
      );
      final later = now.add(const Duration(minutes: 1));
      expect(sceneTrainPositions(scene, later).keys, [_identity]);
      final aged = currentScene(scene, later)!;
      expect(aged.awaitingUpdate.single.number, expired.number);
      expect(aged.awaitingUpdate.single.reason, "stale_report");
      expect(aged.trains.map((row) => row.number), contains(scheduled.number));
      expect(aged.passed, isEmpty);
    },
  );

  test("a wrong gate or malformed train row cannot replace or refresh a valid saved scene", () async {
    final store = DeviceStore(await SharedPreferences.getInstance());
    var reply = _response("A", trains: [_wireTrain]);
    final api = HttpRailApi(
      base: "https://example.test",
      storage: store,
      client: MockClient((_) async => http.Response(jsonEncode(reply), 200)),
    );
    await api.scene(12, 75, "A");
    final raw = store.read("responses") as Map;
    final oldDate = DateTime.now().subtract(const Duration(minutes: 2));
    raw[_sceneKey]["at"] = oldDate.millisecondsSinceEpoch;
    await store.write("responses", raw);

    for (final invalid in [
      _response("B", trains: [_wireTrain], alias: true),
      _response(
        "A",
        trains: [
          _wireTrain,
          {"number": "16603", "status": "closed"},
        ],
      ),
    ]) {
      reply = invalid;
      final result = await api.scene(12, 75, "A");
      expect(result.offline, isTrue);
      expect(result.crossing!.id, "A");
      expect(
        result.savedAt!.millisecondsSinceEpoch,
        oldDate.millisecondsSinceEpoch,
      );
      expect(result.trains.single.number, _trainNumber);
    }
    reply = _response(
      "A",
      trains: [
        {..._wireTrain, "eta_min": 4},
      ],
    );
    final corrected = await api.scene(12, 75, "A");
    expect(corrected.offline, isFalse);
    expect(corrected.trains.single.etaMin, 4);
  });

  test(
    "report claims success only with a valid receipt for the submitted state",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      Map<String, Object?> data = {"error": "report_rejected"};
      final api = HttpRailApi(
        base: "https://example.test",
        storage: store,
        client: MockClient((_) async => http.Response(jsonEncode(data), 200)),
      );
      await expectLater(
        api.report(_gate, "closed"),
        throwsA(isA<RailException>()),
      );
      data = {
        "verified": false,
        "reports": [
          {"state": "open", "at": 1000, "expires_at": 1600},
        ],
      };
      await expectLater(
        api.report(_gate, "closed"),
        throwsA(isA<RailException>()),
      );
      data["reports"] = [
        {"state": "closed", "at": 1000, "expires_at": 1600},
      ];
      expect((await api.report(_gate, "closed")).single["state"], "closed");
    },
  );

  testWidgets("a delayed map mirror can complete within the server budget", (
    tester,
  ) async {
    final api = HttpRailApi(
      base: "https://example.test",
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 42));
        return http.Response('{"gates":[]}', 200);
      }),
    );
    GatesBody? boxes;
    final checking = api.gates(12, 75).then((value) => boxes = value);
    await tester.pump(const Duration(seconds: 42));
    await checking;
    expect(boxes!.authoritative, isTrue);
  });

  test(
    "favorites survive degraded map data but a complete omission retires them",
    () async {
      final api = _AuditApi();
      final rail = RailController(api);
      addTearDown(rail.dispose);
      await rail.choosePlace(12, 75, label: "Sample");
      rail.saveGate(_gate, "Home");
      api.listing = const GatesBody(gates: [], mapWarning: "map_unavailable");
      await rail.openSaved(rail.favorites.single);
      expect(rail.favorites.single.gate.id, "A");
      expect(rail.selected, isNull);
      expect(rail.selectionNote, contains("could not be verified"));
      api.listing = const GatesBody(gates: []);
      await rail.openSaved(rail.favorites.single);
      expect(rail.favorites, isEmpty);
      expect(rail.selected, isNull);
      expect(rail.selectionNote, contains("no longer on the map"));
    },
  );

  test(
    "a missing shared gate identifies the result as an area-only lookup",
    () async {
      final rail = RailController(_AuditApi());
      addTearDown(rail.dispose);
      expect(
        await rail.openLink("https://example.test/?lat=12&lon=75"),
        isTrue,
      );
      expect(rail.selectionNote, isNull);
      expect(
        await rail.openLink("https://example.test/?lat=12&lon=75&gate=old"),
        isTrue,
      );
      expect(rail.selected, isNull);
      expect(rail.place, const Spot(12, 75));
      expect(rail.selectionNote, contains("could not be found"));
    },
  );

  for (final available in [true, false]) {
    test(
      "an explicitly migrated opaque gate replaces a legacy favorite (rail available: $available)",
      () async {
        final api = HttpRailApi(
          base: "https://example.test",
          client: MockClient((request) async {
            switch (request.url.path) {
              case "/gates":
                return http.Response(
                  jsonEncode({
                    "gates": [
                      {"id": _currentId, "lat": 12, "lon": 75},
                    ],
                  }),
                  200,
                );
              case "/scene":
                return http.Response(
                  jsonEncode(
                    _response(_currentId, alias: true, available: available),
                  ),
                  200,
                );
              default:
                return http.Response('{"name":"Sample"}', 200);
            }
          }),
        );
        final rail = RailController(api);
        addTearDown(rail.dispose);
        await rail.choosePlace(12, 75, label: "Sample");
        const old = Gate(
          id: _legacyId,
          name: "Home",
          lat: 12,
          lon: 75,
          km: 0,
          source: "user",
        );
        rail.saveGate(old, "Home");
        expect(
          Uri.parse(crossingLink(old)).queryParameters,
          isNot(contains("gate")),
        );
        await rail.openSaved(rail.favorites.single);
        expect(rail.selected!.id, _currentId);
        expect(rail.scene!.available, available);
        expect(rail.favorites.single.gate.id, _currentId);
        expect(rail.favorites.single.label, "Home");
      },
    );
  }

  test(
    "clearing history keeps favorites and rejects a late map cache write",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final api = HttpRailApi(
        base: "https://example.test",
        storage: store,
        client: MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final rail = RailController(api, storage: store);
      addTearDown(rail.dispose);
      final opening = rail.choosePlace(12, 75, label: "Sample");
      await started.future;
      rail.saveGate(_gate, "Home");
      await rail.clearLocationHistory();
      response.complete(http.Response('{"gates":[]}', 200));
      await opening;
      expect(store.response(_gatesKey), isNull);
      expect(store.read("last-place"), isNull);
      expect(rail.place, isNull);
      expect(store.favorites().single.label, "Home");
    },
  );

  testWidgets("light-theme approaching text stays readable", (tester) async {
    const colors = RailColors.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: railTheme(colors),
        home: const Scaffold(
          body: StatusPip(status: "approaching", label: "Approaching"),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text("APPROACHING"));
    final foreground = text.style!.color!.computeLuminance();
    final background = colors.sheet.computeLuminance();
    expect((background + .05) / (foreground + .05), greaterThan(4.5));
  });
}

class _AuditApi implements RailApi {
  GatesBody listing = const GatesBody(gates: [_gate]);

  @override
  Future<List<CityHit>> cities(String query) async => [];

  @override
  Future<GatesBody> gates(double lat, double lon) async => listing;

  @override
  Future<String?> placeName(double lat, double lon) async => "Sample";

  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();

  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async =>
      const Scene(available: false, error: "crossing_not_found");
}
