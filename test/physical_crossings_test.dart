import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/device_store.dart";
import "package:gateahead/format.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/train_sheet.dart";
import "package:google_fonts/google_fonts.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:shared_preferences/shared_preferences.dart";

Map<String, dynamic> _gateJson(int id, {String group = "road:1"}) => {
  "id": "osm:$id",
  "name": "Near Trikaripur",
  "lat": 12.0,
  "lon": 75.0 + id / 100000,
  "km": id / 10,
  "source": "osm",
  "group_id": group,
  "group_name": group.isEmpty ? "" : "School Road crossing",
  "group_size": group.isEmpty ? 1 : 2,
  "road": "School Road",
  "area": "Trikaripur",
};

List<Gate> _gates() => [
  Gate.tryParse(_gateJson(1))!,
  Gate.tryParse(_gateJson(2))!,
];

Approach _approach(
  String id, {
  String train = "16512",
  String date = "2026-11-16",
  String? runId,
  double eta = 6,
  List<String>? ids,
}) => Approach.tryParse({
  "train": train,
  "name": "Coastal Express",
  "start_date": date,
  "run_id": ?runId,
  "cluster": "Near Trikaripur",
  "ids": ids ?? [id],
  "eta": eta,
  "closes_in": eta - 5,
  "status": eta < 5 ? "closed" : "closing_soon",
})!;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    RailThemeScope(
      onToggle: () {},
      child: MaterialApp(
        theme: railTheme(RailColors.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  test(
    "optional metadata parses safely and survives copies and gate marks",
    () {
      final gates = _gates();
      final copied = gates.first.copyWith(name: "Home");
      final marked = markGates(
        gates,
        Predict(approaching: [_approach("osm:1")]),
      );
      for (final gate in [copied, ...marked]) {
        expect(gate.groupId, "road:1");
        expect(gate.groupName, "School Road crossing");
        expect(gate.groupSize, 2);
        expect(gate.road, "School Road");
        expect(gate.area, "Trikaripur");
      }
      expect(marked.first.id, "osm:1");
      expect(marked.first.eta, 6);
      expect(marked.last.eta, isNull);
      final older = Gate.tryParse({"id": "old", "lat": 12, "lon": 75})!;
      expect(older.groupId, isEmpty);
      expect(older.groupSize, 1);
      final malformed = Gate.tryParse({
        ..._gateJson(1),
        "group_id": {},
        "group_name": [],
        "group_size": -1,
      })!;
      expect(malformed.groupId, isEmpty);
      expect(malformed.groupName, isEmpty);
      expect(malformed.groupSize, 1);
    },
  );

  test("nearby names and coordinates alone never group crossings", () {
    final samePlace = [
      ..._gates(),
      Gate.tryParse(_gateJson(3, group: ""))!,
      Gate.tryParse(_gateJson(4, group: ""))!,
      Gate.tryParse(_gateJson(5, group: "road:2"))!,
    ];
    final groups = physicalCrossings(samePlace);
    expect(groups.length, 4);
    expect(groups.first.members.map((gate) => gate.id), ["osm:1", "osm:2"]);
    expect(groups.first.name, "School Road crossing");
    expect(groups.skip(1).every((group) => group.members.length == 1), isTrue);
  });

  test(
    "nearby limits count physical roads and keep all active group members",
    () {
      final gates = [
        for (var i = 1; i <= 30; i++)
          Gate.tryParse(_gateJson(i, group: "road:${(i + 1) ~/ 2}"))!,
      ];
      final inactive = shownCrossings(gates);
      expect(inactive.length, 12);
      expect(inactive.every((group) => group.members.length == 2), isTrue);
      final active = shownCrossings(
        markGates(gates, Predict(approaching: [_approach("osm:29", eta: 2)])),
      );
      expect(active.length, 13);
      expect(active.first.members.map((gate) => gate.id), ["osm:29", "osm:30"]);
    },
  );

  test(
    "track groups preserve dated runs, distinct run IDs, and other trains",
    () {
      final rows = [
        for (final date in ["2026-11-15", "2026-11-16"])
          for (final id in ["osm:1", "osm:2"]) _approach(id, date: date),
        for (final runId in ["special-a", "special-b"])
          for (final id in ["osm:1", "osm:2"]) _approach(id, runId: runId),
        for (final id in ["osm:1", "osm:2"]) _approach(id, train: "16650"),
      ];
      final grouped = crossingApproaches(rows, _gates());
      expect(grouped.length, 5);
      for (final crossing in grouped) {
        expect(crossing.grouped, isTrue);
        expect(crossing.rows.length, 2);
        expect(crossing.rows.map((row) => row.identity).toSet().length, 1);
        expect(crossing.ids, {"osm:1", "osm:2"});
      }
    },
  );

  test(
    "unknown IDs and broad existing clusters retain their individual rows",
    () {
      final gates = [
        ..._gates(),
        Gate.tryParse(_gateJson(3, group: "road:2"))!,
      ];
      final rows = [
        _approach("osm:1"),
        _approach("osm:2", ids: ["osm:2", "osm:3"]),
        _approach("unknown"),
        _approach("osm:2", ids: ["osm:2", "unknown"]),
      ];
      expect(crossingApproaches(rows, gates).length, rows.length);
      expect(crossingApproaches(rows, []).length, rows.length);
      final repeated = crossingApproaches([
        _approach("osm:1"),
        _approach("osm:1", eta: 9),
      ], gates);
      expect(repeated.length, 2);
      expect(repeated.expand((group) => group.rows).length, 2);
    },
  );

  test(
    "group metadata survives online, offline, and saved gate restoration",
    () async {
      final storage = DeviceStore(await SharedPreferences.getInstance());
      var offline = false;
      final api = HttpRailApi(
        base: "https://example.test",
        storage: storage,
        client: MockClient((request) async {
          if (offline) throw Exception("offline");
          return http.Response(
            jsonEncode({
              "gates": [_gateJson(1), _gateJson(2)],
            }),
            200,
          );
        }),
      );
      final fresh = await api.gates(12, 75);
      offline = true;
      final cached = await api.gates(12, 75);
      expect(cached.offline, isTrue);
      expect(cached.savedAt, fresh.savedAt);
      expect(physicalCrossings(cached.gates).single.members.length, 2);
      final rail = RailController(_GroupedApi(), storage: storage);
      addTearDown(rail.dispose);
      rail.place = const Spot(12, 75);
      rail.saveGate(cached.gates.last, "Home");
      await Future<void>.delayed(Duration.zero);
      final restarted = RailController(_GroupedApi(), storage: storage);
      addTearDown(restarted.dispose);
      final saved = restarted.favorites.single.gate;
      expect(saved.id, "osm:2");
      expect(saved.groupId, "road:1");
      expect(saved.groupName, "School Road crossing");
      expect(saved.groupSize, 2);
      expect(saved.road, "School Road");
      expect(saved.area, "Trikaripur");
    },
  );

  test(
    "a checked track updates its raw ID without clearing its sibling warning",
    () async {
      final api = _GroupedApi();
      final rail = RailController(api);
      addTearDown(rail.dispose);
      await rail.choosePlace(12, 75, label: "Trikaripur");
      rail.predict = Predict.parse({
        "_saved_at": DateTime.now().millisecondsSinceEpoch,
        "approaching": [],
        "awaiting_update": [
          {
            "number": "16512",
            "ids": ["osm:1", "osm:2"],
          },
        ],
      });
      expect(physicalCrossings(rail.markedGates).single.uncertainCount, 2);
      await rail.openGate(rail.gates.first);
      final group = physicalCrossings(rail.markedGates).single;
      expect(api.sceneIds, ["osm:1"]);
      expect(group.members.first.status, isNull);
      expect(group.members.last.status, "uncertain");
      expect(group.uncertainCount, 1);
      expect(group.members.every((gate) => gate.groupId == "road:1"), isTrue);
    },
  );

  test(
    "exact gate timings split broad clusters within the matching journey",
    () {
      final gates = [
        ..._gates(),
        Gate.tryParse(_gateJson(3, group: "road:2"))!,
        Gate.tryParse(_gateJson(4, group: "road:2"))!,
      ];
      final prediction = Predict(
        approaching: [
          _approach(
            "osm:1",
            date: "2026-11-15",
            ids: ["osm:1", "osm:2", "osm:3", "osm:4"],
            eta: 1,
          ),
          _approach(
            "osm:1",
            date: "2026-11-16",
            ids: ["osm:1", "osm:2"],
            eta: 20,
          ),
        ],
        gatePredictions: [
          for (var i = 1; i <= 3; i++)
            GatePrediction(
              id: "osm:$i",
              train: "16512",
              startDate: "2026-11-15",
              eta: i * 4,
              closesIn: i * 4 - 5,
              status: i == 1 ? "closed" : "closing_soon",
            ),
          const GatePrediction(
            id: "osm:2",
            train: "16512",
            runId: "other-run",
            startDate: "2026-11-16",
            eta: 99,
            status: "later",
          ),
        ],
      );
      final rows = trainCrossingRows(prediction, gates);
      final old = rows.where((row) => row.startDate == "2026-11-15").toList();
      final fresh = rows.where((row) => row.startDate == "2026-11-16").toList();
      expect(old.map((row) => row.ids.single), ["osm:1", "osm:2", "osm:3"]);
      expect(old.map((row) => row.eta), [4, 8, 12]);
      expect(old.map((row) => row.closesIn), [-1, 3, 7]);
      expect(old.every((row) => row.count == 1), isTrue);
      final groups = crossingApproaches(old, gates);
      expect(groups.length, 2);
      expect(groups.first.ids, {"osm:1", "osm:2"});
      expect(groups.last.ids, {"osm:3"});
      expect(fresh.single.ids, ["osm:1", "osm:2"]);
      expect(fresh.single.eta, 20);
      expect(
        trainCrossingRows(
          Predict(approaching: prediction.approaching),
          gates,
        ).length,
        2,
      );
    },
  );

  test(
    "malformed optional grouping metadata cannot replace a valid cached body",
    () {
      for (final value in [
        {"group_id": []},
        {"group_name": {}},
        {"road": 1},
        {"area": false},
        {"group_size": 0},
        {"group_size": 2.5},
      ]) {
        expect(
          validResponseBody("/gates", {
            "gates": [
              {..._gateJson(1), ...value},
            ],
          }),
          isFalse,
        );
      }
      expect(
        validResponseBody("/gates", {
          "gates": [_gateJson(1)],
        }),
        isTrue,
      );
      expect(
        validResponseBody("/gates", {
          "gates": [
            {"id": "old", "lat": 12, "lon": 75},
          ],
        }),
        isTrue,
      );
    },
  );

  testWidgets(
    "nearby group expands to precise tracks with conservative mixed status",
    (tester) async {
      final api = _GroupedApi();
      final rail = RailController(api);
      addTearDown(rail.dispose);
      await rail.choosePlace(12, 75, label: "Trikaripur");
      rail.predict = Predict.parse({
        "approaching": [],
        "gate_predictions": [
          {
            "id": "osm:1",
            "train": "16650",
            "eta": 2,
            "closes_in": -3,
            "status": "closed",
          },
        ],
        "awaiting_update": [
          {
            "number": "16512",
            "ids": ["osm:2"],
          },
        ],
      });
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _pump(
        tester,
        TrainSheet(rail: rail, onLocate: () {}, scroll: scroll),
      );
      expect(find.text("Trikaripur · 1 crossing on this map."), findsOneWidget);
      expect(find.text("School Road crossing"), findsOneWidget);
      expect(
        find.textContaining("Position update needed on 1 track"),
        findsOneWidget,
      );
      expect(
        find.textContaining("Other track estimate: closed · train in 2 min"),
        findsOneWidget,
      );
      expect(find.text("Track 2 · osm:2"), findsNothing);
      await _tap(tester, find.text("School Road crossing"));
      expect(find.text("Track 1 · osm:1"), findsOneWidget);
      expect(find.text("Track 2 · osm:2"), findsOneWidget);
      await _tap(tester, find.text("Track 2 · osm:2"));
      expect(api.sceneIds, ["osm:2"]);
      expect(rail.selected?.id, "osm:2");
      expect(
        find.textContaining("Track crossing osm:2 · part of 2"),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    "train cards group track rows per date and expose each estimate",
    (tester) async {
      final prediction = Predict(
        approaching: [
          for (final date in ["2026-11-15", "2026-11-16"])
            _approach("osm:1", date: date, eta: 2, ids: ["osm:1", "osm:2"]),
          _approach("osm:1", train: "16650", eta: 8),
          _approach("osm:2", train: "16650", eta: 9),
        ],
        gatePredictions: [
          for (final date in ["2026-11-15", "2026-11-16"]) ...[
            GatePrediction(
              id: "osm:1",
              train: "16512",
              startDate: date,
              eta: 2,
              closesIn: -3,
              status: "closed",
            ),
            GatePrediction(
              id: "osm:2",
              train: "16512",
              startDate: date,
              eta: 6,
              closesIn: 1,
              status: "closing_soon",
            ),
          ],
        ],
      );
      await _pump(
        tester,
        SingleChildScrollView(
          child: PredictBody(predict: prediction, gates: _gates()),
        ),
      );
      expect(find.text("School Road crossing"), findsNWidgets(3));
      expect(find.textContaining("Started 2026-11-15"), findsOneWidget);
      expect(find.textContaining("Started 2026-11-16"), findsNWidgets(2));
      expect(
        find.textContaining("2 track crossings · Earliest estimate:"),
        findsNWidgets(3),
      );
      expect(find.text("Track crossing osm:1"), findsNothing);
      await _tap(
        tester,
        find.byKey(const ValueKey("train-crossing:16512:2026-11-15:road:1")),
      );
      expect(find.text("Track crossing osm:1"), findsOneWidget);
      expect(find.text("Track crossing osm:2"), findsOneWidget);
      expect(find.text("closed · train in 2 min"), findsOneWidget);
      expect(find.text("closes in 1 min"), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    "320px phone with larger text can expand and select a mixed-status track",
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _GroupedApi();
      final rail = RailController(api);
      addTearDown(rail.dispose);
      await rail.choosePlace(12, 75, label: "Trikaripur");
      rail.predict = Predict.parse({
        "approaching": [],
        "gate_predictions": [
          {"id": "osm:1", "eta": 2, "closes_in": -3, "status": "closed"},
        ],
        "awaiting_update": [
          {
            "number": "16512",
            "ids": ["osm:2"],
          },
        ],
      });
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _pump(
        tester,
        TrainSheet(rail: rail, onLocate: () {}, scroll: scroll),
        textScale: 1.4,
      );
      await tester.scrollUntilVisible(find.text("School Road crossing"), 120);
      await _tap(tester, find.text("School Road crossing"));
      await _tap(tester, find.text("Track 2 · osm:2"));
      expect(rail.selected?.id, "osm:2");
      expect(api.sceneIds, ["osm:2"]);
      expect(tester.takeException(), isNull);
    },
  );
}

class _GroupedApi implements RailApi {
  final sceneIds = <String>[];
  @override
  Future<List<CityHit>> cities(String query) async => [];
  @override
  Future<String?> placeName(double lat, double lon) async => "Trikaripur";
  @override
  Future<GatesBody> gates(double lat, double lon) async =>
      GatesBody(gates: _gates());
  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();
  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async {
    sceneIds.add(crossingId);
    return Scene(
      available: true,
      savedAt: DateTime.now(),
      crossing: SceneCrossing(
        id: crossingId,
        name: "Near Trikaripur",
        lat: 12,
        lon: 75,
      ),
      rail: const [Spot(11.99, 75), Spot(12.01, 75)],
    );
  }
}
