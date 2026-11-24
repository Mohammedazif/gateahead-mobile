import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/commutes.dart";
import "package:gateahead/device_store.dart";
import "package:gateahead/models.dart";
import "package:gateahead/phone_alerts.dart";
import "package:gateahead/phone_push.dart";
import "package:gateahead/rail_controller.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/crossing_access.dart";
import "package:gateahead/ui/phone_alert_controls.dart";
import "package:google_fonts/google_fonts.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:shared_preferences/shared_preferences.dart";

const _school = Gate(
  id: "osm:node:1",
  name: "School Road",
  lat: 12,
  lon: 75,
  km: 0.2,
  source: "osm",
);
const _work = Gate(
  id: "osm:node:2",
  name: "Station Road",
  lat: 12.01,
  lon: 75.01,
  km: 1,
  source: "osm",
);
const _saved = [
  SavedGate(_school, "Home gate", Spot(12, 75)),
  SavedGate(_work, "Work gate", Spot(12, 75)),
];

http.Response _reply(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Map<String, dynamic> _status(
  int revision,
  int registered, {
  bool verified = false,
}) => {
  "enabled": true,
  "status": "ready",
  "registered": registered,
  "revision": revision,
  "fid_verified": verified,
};

Future<DeviceStore> _store() async =>
    DeviceStore(await SharedPreferences.getInstance());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("commute checks retain gate order without opening a crossing", () async {
    final store = await _store();
    final requested = <String>[];
    final api = HttpRailApi(
      base: "https://example.test",
      storage: store,
      client: MockClient((request) async {
        final id = request.url.queryParameters["crossing_id"]!;
        requested.add(id);
        return _reply({
          "available": true,
          "crossing": {"id": id, "lat": 12, "lon": 75},
          "trains": [],
          if (id == _school.id) "coverage": {"status": "partial"},
        });
      }),
    );
    await store.write("favorites", [for (final gate in _saved) gate.toJson()]);
    final rail = RailController(api, storage: store);
    addTearDown(rail.dispose);
    await rail.commutes.save("Work commute", [_work.id, _school.id, _work.id]);
    final trip = rail.commutes.trips.single;
    await rail.commutes.check(trip, rail.favorites);
    expect(requested, [_work.id, _school.id]);
    expect(rail.selected, isNull);
    expect(rail.place, isNull);
    expect(
      rail.commutes.results[trip.id]![_school.id]!.summary,
      contains("unknown"),
    );
    final restored = RailController(api, storage: store);
    addTearDown(restored.dispose);
    expect(restored.commutes.trips.single.gateIds, [_work.id, _school.id]);
    expect(restored.commutes.results[trip.id]![_work.id]!.historical, isTrue);
    expect(
      restored.commutes.results[trip.id]![_work.id]!.at,
      rail.commutes.results[trip.id]![_work.id]!.at,
    );
  });

  test("commute timing ages a report and retains unresolved trains", () {
    final at = DateTime.now().subtract(const Duration(seconds: 75));
    final check = CommuteGateCheck(
      _school.id,
      at: at,
      scene: Scene(
        available: true,
        savedAt: at,
        trains: const [
          SceneTrain(
            number: "16603",
            name: "Test express",
            etaMin: 4,
            closesInMin: 1,
            status: "closing_soon",
            alongKm: 1,
            ageMin: 1,
          ),
        ],
        awaitingUpdate: const [
          AwaitingTrain(
            number: "16601",
            name: "Other service",
            current: "Unknown",
            ageMin: 9,
          ),
        ],
      ),
    );
    expect(check.historical, isFalse);
    expect(check.summary, startsWith("Estimated closure window"));
    expect(check.notice, contains("Barrier timing is unknown"));
  });

  test(
    "a failed commute keeps earlier checks and the longest shared pause",
    () async {
      final store = await _store();
      final at = DateTime.now().subtract(const Duration(minutes: 5));
      for (final item in _saved) {
        await store.saveResponse(
          sceneResponseKey(item.place.lat, item.place.lon, item.gate.id),
          {
            "available": true,
            "crossing": {
              "id": item.gate.id,
              "lat": item.gate.lat,
              "lon": item.gate.lon,
            },
            "trains": [],
          },
          receivedAt: at,
        );
      }
      await store.write("favorites", [
        for (final gate in _saved) gate.toJson(),
      ]);
      await store.write("commutes", [
        SavedCommute("trip", "Trip", [_school.id, _work.id]).toJson(),
      ]);
      final api = HttpRailApi(
        base: "https://example.test",
        storage: store,
        client: MockClient((request) async {
          final second = request.url.queryParameters["crossing_id"] == _work.id;
          if (second) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          return http.Response(
            "{}",
            429,
            headers: {"retry-after": second ? "600" : "60"},
          );
        }),
      );
      final rail = RailController(api, storage: store);
      addTearDown(rail.dispose);
      await rail.checkCommute(rail.commutes.trips.single);
      final now = DateTime.now();
      expect(
        rail.railPause!.difference(now).inMinutes,
        greaterThanOrEqualTo(9),
      );
      expect(store.railPause, rail.railPause);
      final earlier = rail.commutes.results["trip"]![_school.id]!;
      expect(earlier.at!.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
      expect(earlier.notice, contains("Check paused"));
    },
  );

  test(
    "deleting a commute cancels queued scenes and discards late results",
    () async {
      final store = await _store();
      final saved = [
        for (var i = 1; i <= 6; i++)
          SavedGate(
            Gate(
              id: "osm:node:$i",
              name: "Gate $i",
              lat: 12.0,
              lon: 75.0,
              km: 1,
              source: "osm",
            ),
            "Gate $i",
            const Spot(12, 75),
          ),
      ];
      await store.write("favorites", [for (final gate in saved) gate.toJson()]);
      final started = Completer<void>();
      final complete = Completer<void>();
      var requests = 0;
      final api = HttpRailApi(
        base: "https://example.test",
        storage: store,
        client: MockClient((request) async {
          requests++;
          if (requests == 2) started.complete();
          await complete.future;
          return _reply({
            "available": true,
            "crossing": {
              "id": request.url.queryParameters["crossing_id"]!,
              "lat": 12,
              "lon": 75,
            },
            "trains": [],
          });
        }),
      );
      final rail = RailController(api, storage: store);
      addTearDown(rail.dispose);
      await rail.commutes.save("Trip", [
        for (final gate in saved) gate.gate.id,
      ]);
      final trip = rail.commutes.trips.single;
      final checking = rail.checkCommute(trip);
      await started.future;
      rail.commutes.remove(trip);
      complete.complete();
      await checking;
      expect(requests, 2);
      expect(rail.commutes.results, isEmpty);
      expect(
        store.response(sceneResponseKey(12, 75, saved.first.gate.id)),
        isNull,
      );
    },
  );

  test("a commute check migrates legacy crossing IDs and restores its canonical result", () async {
    final store = await _store();
    const legacy = Gate(
      id: "user:123:1000",
      name: "Saved crossing",
      lat: 12,
      lon: 75,
      km: 0.2,
      source: "manual",
    );
    const canonical = "pin:0123456789abcdef0123456789abcdef";
    await store.write("favorites", [
      const SavedGate(legacy, "School run", Spot(12, 75)).toJson(),
    ]);
    final api = HttpRailApi(
      base: "https://example.test",
      storage: store,
      client: MockClient((request) async {
        expect(request.url.queryParameters["crossing_id"], legacy.id);
        return _reply({
          "available": true,
          "crossing": {"id": canonical, "lat": 12, "lon": 75},
          "legacy_alias_resolved": true,
          "trains": [],
        });
      }),
    );
    final rail = RailController(api, storage: store);
    addTearDown(rail.dispose);
    await rail.commutes.save("Trip", [legacy.id]);
    await rail.checkCommute(rail.commutes.trips.single);
    await Future<void>.delayed(Duration.zero);
    expect(rail.favorites.single.gate.id, canonical);
    expect(rail.selected, isNull);
    final restored = RailController(api, storage: store);
    addTearDown(restored.dispose);
    final trip = restored.commutes.trips.single;
    expect(trip.gateIds, [canonical]);
    expect(restored.commutes.results[trip.id]![canonical]?.historical, isTrue);
  });

  test("old commute checks show timing as an estimate from the old check", () {
    final at = DateTime.now().subtract(const Duration(minutes: 3));
    final check = CommuteGateCheck(
      _school.id,
      at: at,
      scene: Scene(
        available: true,
        savedAt: at,
        trains: const [
          SceneTrain(
            number: "16603",
            name: "Test express",
            etaMin: 6,
            status: "closing_soon",
            alongKm: 1,
            ageMin: 1,
          ),
        ],
      ),
    );
    expect(check.historical, isTrue);
    expect(check.summary, "Train was due in 6 min at check");
    expect(check.nextTrain!.number, "16603");
  });

  test("crossing access keeps verified bypasses and confirms a flag", () async {
    final store = await _store();
    final api = HttpRailApi(
      base: "https://example.test",
      storage: store,
      client: MockClient((request) async {
        if (request.method == "POST") {
          expect(request.url.path, "/crossing-details/flags");
          final body = jsonDecode(request.body) as Map;
          expect(body["crossing_id"], _school.id);
          expect(body["installation_id"], isNotEmpty);
          return _reply({"accepted": true}, 202);
        }
        return _reply({
          "available": false,
          "crossing": {"id": _school.id, "lat": 12, "lon": 75},
          "rail": [],
          "trains": [],
          "passed": [],
          "crossing_access": {
            "source": "mapped",
            "cars": "restricted",
            "two_wheelers": "unknown",
            "pedestrians": "allowed",
            "bypasses": [
              {
                "kind": "underpass",
                "name": "School Road underpass",
                "lat": 12.001,
                "lon": 75,
                "verified_on": "2026-11-20",
                "replacement": true,
              },
              {
                "kind": "flyover",
                "name": "Incomplete entry",
                "lat": 12.002,
                "lon": 75,
              },
            ],
          },
        });
      }),
    );
    final scene = await api.scene(_school.lat, _school.lon, _school.id);
    final access = scene.crossingAccess!;
    expect(access.cars, RoadAccess.restricted);
    expect(access.twoWheelers, RoadAccess.unknown);
    expect(access.pedestrians, RoadAccess.allowed);
    expect(access.bypasses.single.replacement, isTrue);
    expect(
      scene.asSaved().crossingAccess?.bypasses.single.name,
      "School Road underpass",
    );
    await api.flagCrossingDetails(_school);
  });

  test("valid independent crossing details arrive while the train check is pending", () async {
    final train = Completer<http.Response>();
    final detailsReady = Completer<void>();
    final api = HttpRailApi(
      base: "https://example.test",
      client: MockClient((request) async {
        switch (request.url.path) {
          case "/gates":
            return _reply({
              "gates": [
                {"id": _school.id, "lat": 12, "lon": 75, "name": "School Road"},
              ],
            });
          case "/crossing-details":
            expect(request.url.queryParameters["lat"], "12.0");
            return _reply({
              "crossing": {"id": _school.id, "lat": 12, "lon": 75},
              "crossing_access": {"source": "mapped", "cars": "allowed"},
            });
          case "/scene":
            return train.future;
          default:
            return _reply({});
        }
      }),
    );
    final rail = RailController(api);
    addTearDown(rail.dispose);
    await rail.choosePlace(12, 75, label: "School");
    rail.addListener(() {
      if (rail.crossingAccess != null && !detailsReady.isCompleted) {
        detailsReady.complete();
      }
    });
    final checking = rail.openGate(_school);
    await detailsReady.future;
    expect(rail.sceneLoading, isTrue);
    expect(rail.crossingAccess?.cars, RoadAccess.allowed);
    train.complete(_reply({"available": false, "trains": []}));
    await checking;
    expect(rail.crossingAccess?.cars, RoadAccess.allowed);
  });

  test("unavailable and stale verified access forgets old permissions", () {
    final raw = CrossingAccess.tryParse({
      "source": "verified",
      "verified_on": "2025-11-22",
      "cars": "allowed",
      "bypasses": [
        {
          "kind": "underpass",
          "name": "School bridge",
          "lat": 12,
          "lon": 75,
          "verified_on": "2026-11-20",
        },
      ],
    })!;
    final access = raw.current(DateTime.utc(2026, 11, 24));
    expect(access.source, "unavailable");
    expect(access.cars, RoadAccess.unknown);
    expect(access.bypasses.single.name, "School bridge");
  });

  test(
    "phone enrollment buffers early proof and revokes after an offline restart",
    () async {
      final store = await _store();
      final push = _Push();
      addTearDown(push.close);
      final calls = <Map<String, dynamic>>[];
      var connected = true;
      final api = HttpRailApi(
        base: "https://example.test",
        client: MockClient((request) async {
          if (!connected) throw StateError("offline");
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          switch (request.url.path) {
            case "/phone-alerts/status":
              return _reply(_status(0, 0));
            case "/phone-alerts/challenge":
              expect(body["fid"], _Push.fid);
              expect(body["revision"], 1);
              push.proofs.add(
                const PhoneAlertChallenge(
                  "challenge_fixture_2026",
                  "proof_fixture_2026",
                ),
              );
              return _reply({
                "challenge_id": "challenge_fixture_2026",
                "expires_in": 5,
              });
            default:
              calls.add(body);
              final count = (body["gates"] as List).length;
              return _reply(
                _status(body["revision"] as int, count, verified: count > 0),
              );
          }
        }),
      );
      final first = PhoneAlerts(api, store, push, () => _saved);
      await first.save(_saved.first, const PhoneAlertSettings(leadMinutes: 15));
      expect(first.pending, isFalse);
      expect(first.badge, "registered");
      expect(calls.single["challenge_id"], "challenge_fixture_2026");
      expect(calls.single["challenge_response"], "proof_fixture_2026");
      final gate = (calls.single["gates"] as List).single as Map;
      expect(gate["lead_minutes"], 15);
      expect(gate.containsKey("name"), isFalse);
      final key = calls.single["device_key"];
      expect(key, matches(r"^[0-9a-f]{64}$"));
      connected = false;
      await first.remove(_school.id);
      expect(first.pending, isTrue);
      expect(first.hasAlerts, isFalse);
      expect(push.disconnects, 1);
      first.dispose();

      connected = true;
      final second = PhoneAlerts(api, store, push, () => _saved);
      addTearDown(second.dispose);
      await second.resume();
      expect(second.pending, isFalse);
      expect(calls.last, {
        "device_key": key,
        "fid": null,
        "revision": 2,
        "gates": [],
      });
      expect((store.read("phone-alerts") as Map)["revision"], 2);
      expect(push.disconnects, 1);
    },
  );

  test("phone alerts renew a saved registration without prompting and report a permission revoke", () async {
    final store = await _store();
    final push = _Push();
    addTearDown(push.close);
    await store.write("phone-alerts", {
      "device_key": "a" * 64,
      "fid": _Push.fid,
      "revision": 4,
      "synced_at": DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch,
      "gates": {_school.id: const PhoneAlertSettings().toJson()},
    });
    final writes = <Map<String, dynamic>>[];
    var serverRevision = 4;
    final api = HttpRailApi(
      base: "https://example.test",
      client: MockClient((request) async {
        if (request.url.path == "/phone-alerts/status") {
          return _reply(_status(serverRevision, 1, verified: true));
        }
        expect(request.url.path, "/phone-alerts");
        writes.add(jsonDecode(request.body) as Map<String, dynamic>);
        serverRevision = writes.last["revision"] as int;
        return _reply(_status(serverRevision, 1, verified: true));
      }),
    );
    final alerts = PhoneAlerts(api, store, push, () => _saved);
    addTearDown(alerts.dispose);
    await alerts.resume();
    await alerts.resume();
    expect(writes.single["fid"], _Push.fid);
    expect(writes.single["revision"], 5);
    expect(push.requests, 0);
    expect(alerts.pending, isFalse);
    push.allowed = false;
    await alerts.resume();
    expect(alerts.badge, "device permission off");
    expect(writes, hasLength(1));
  });

  test("conflicting alert revisions wait for explicit retry", () async {
    final store = await _store();
    final push = _Push();
    addTearDown(push.close);
    await store.write("phone-alerts", {
      "device_key": "a" * 64,
      "fid": _Push.fid,
      "revision": 2,
      "pending": true,
      "gates": {_school.id: const PhoneAlertSettings().toJson()},
    });
    final writes = <int>[];
    final api = HttpRailApi(
      base: "https://example.test",
      client: MockClient((request) async {
        if (request.url.path == "/phone-alerts/status") {
          return _reply(_status(4, 1, verified: true));
        }
        expect(request.url.path, "/phone-alerts");
        writes.add((jsonDecode(request.body) as Map)["revision"] as int);
        return _reply(_status(writes.last, 1, verified: true));
      }),
    );
    final alerts = PhoneAlerts(api, store, push, () => _saved);
    addTearDown(alerts.dispose);
    await alerts.resume();
    await alerts.resume();
    expect(writes, isEmpty);
    expect(alerts.message, contains("Review your choices"));
    await alerts.sync(interactive: true);
    expect(writes, [5]);
    expect(alerts.pending, isFalse);
  });

  for (final turningOff in [false, true]) {
    testWidgets(
      "late phone alert ${turningOff ? 'turn-off' : 'save'} keeps the parent route",
      (tester) async {
        final alerts = _DialogAlerts(turningOff);
        addTearDown(alerts.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => showPhoneAlertSettings(
                            context,
                            alerts,
                            _saved.first,
                          ),
                          child: const Text("Saved page"),
                        ),
                      ),
                    ),
                  ),
                  child: const Text("Open saved"),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text("Open saved"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("Saved page"));
        await tester.pumpAndSettle();
        await tester.tap(find.text(turningOff ? "Turn off" : "Save alerts"));
        await tester.pumpAndSettle();
        expect(alerts.saving, isTrue);
        await tester.tap(find.text("Close"));
        await tester.pump();
        alerts.reply.complete();
        await tester.pumpAndSettle();
        expect(alerts.pending, isFalse);
        expect(find.text("Saved page"), findsOneWidget);
      },
    );
  }

  for (final colors in [RailColors.light, RailColors.dark]) {
    testWidgets(
      "narrow crossing controls reflow at 2x text in ${colors.mode.name}",
      (tester) async {
        GoogleFonts.config.allowRuntimeFetching = false;
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final api = HttpRailApi(base: "https://example.test");
        await tester.pumpWidget(
          MaterialApp(
            theme: railTheme(colors),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: CrossingAccessDetails(
                  gate: _school,
                  api: api,
                  access: const CrossingAccess(
                    cars: RoadAccess.restricted,
                    twoWheelers: RoadAccess.unknown,
                    pedestrians: RoadAccess.allowed,
                    verifiedOn: null,
                    bypasses: [],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text("Restricted"), findsOneWidget);
      },
    );
  }
}

class _Push implements PhonePushRegistration {
  static const fid = "fixture_installation_17";
  final changes = StreamController<String>.broadcast(sync: true);
  final proofs = StreamController<PhoneAlertChallenge>.broadcast(sync: true);
  int requests = 0, disconnects = 0;
  bool allowed = true;

  @override
  Stream<String> get installationIdChanges => changes.stream;

  @override
  Stream<PhoneAlertChallenge> get challenges => proofs.stream;

  @override
  Future<bool> notificationPermission() async => allowed;

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<String?> requestInstallationId() async {
    requests++;
    if (!allowed) return null;
    changes.add(fid);
    return fid;
  }

  Future<void> close() async {
    await changes.close();
    await proofs.close();
  }
}

class _DialogAlerts extends PhoneAlerts {
  _DialogAlerts(this.turningOff)
    : super(
        HttpRailApi(base: "https://example.test"),
        null,
        null,
        () => _saved,
      );

  final bool turningOff;
  final reply = Completer<void>();

  @override
  bool get canSetUp => true;

  @override
  PhoneAlertSettings? settingsFor(String id) =>
      turningOff ? const PhoneAlertSettings() : null;

  @override
  Future<void> save(SavedGate gate, PhoneAlertSettings settings) => _change();

  @override
  Future<void> remove(String id) => _change();

  Future<void> _change() async {
    pending = true;
    saving = true;
    notifyListeners();
    await reply.future;
    pending = false;
    saving = false;
    notifyListeners();
  }
}
