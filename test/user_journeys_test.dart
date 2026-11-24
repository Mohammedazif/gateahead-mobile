import "dart:async";
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/device_store.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:shared_preferences/shared_preferences.dart";

const _gate = Gate(
  id: "school",
  name: "School Road",
  lat: 12,
  lon: 75,
  km: 0.4,
  source: "osm",
);

Map<String, Object?> _sceneBody(String name) => {
  "available": true,
  "crossing": {"id": _gate.id, "name": name, "lat": 12, "lon": 75},
  "rail": [
    [11.99, 75],
    [12.01, 75],
  ],
  "trains": [],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    "closing then reopening a gate cannot save a late obsolete scene",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      final replies = <Completer<http.Response>>[];
      final api = HttpRailApi(
        base: "https://example.test",
        storage: store,
        client: MockClient((request) async {
          if (request.url.path == "/gates") {
            return http.Response(jsonEncode({"gates": []}), 200);
          }
          if (request.url.path == "/crossing-details") {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          final reply = Completer<http.Response>();
          replies.add(reply);
          return reply.future;
        }),
      );
      final rail = RailController(api, storage: store);
      addTearDown(rail.dispose);
      await rail.choosePlace(12, 75, label: "Kannur");
      final first = rail.openGate(_gate);
      await Future<void>.delayed(Duration.zero);
      rail.closeScene();
      final second = rail.openGate(_gate);
      await Future<void>.delayed(Duration.zero);
      replies[1].complete(
        http.Response(jsonEncode(_sceneBody("New check")), 200),
      );
      await second;
      replies[0].complete(
        http.Response(jsonEncode(_sceneBody("Obsolete check")), 200),
      );
      await first;
      expect(rail.scene!.crossing!.name, "New check");
      rail.closeScene();
      await rail.openGate(_gate);
      expect(rail.scene!.crossing!.name, "New check");
      expect(
        replies,
        hasLength(2),
        reason: "the latest snapshot should be reused",
      );
    },
  );

  for (final badRow in [
    null,
    {"at": "broken", "data": {}},
    {"at": 1},
    [],
  ]) {
    test(
      "a malformed sibling cache row does not break a fresh crossing lookup: $badRow",
      () async {
        final store = DeviceStore(await SharedPreferences.getInstance());
        await store.write("responses", {"broken-key": badRow});
        final api = HttpRailApi(
          base: "https://example.test",
          storage: store,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                "gates": [
                  {"id": "school", "name": "School Road", "lat": 12, "lon": 75},
                ],
              }),
              200,
            ),
          ),
        );
        final result = await api.gates(12, 75);
        expect(result.gates.single.id, "school");
        expect(store.response(responseKey("/gates", 12, 75)), isNotNull);
      },
    );
  }

  for (final body in [
    {"approaching": "old-format"},
    {"approaching": [], "passed": {}},
  ]) {
    test(
      "returning to a place skips unusable saved predictions: $body",
      () async {
        final store = DeviceStore(await SharedPreferences.getInstance());
        await store.write("responses", {
          responseKey("/predict", 12, 75): {
            "at": DateTime.now().millisecondsSinceEpoch,
            "data": body,
          },
        });
        final rail = RailController(_IdleApi(), storage: store);
        addTearDown(rail.dispose);
        await rail.choosePlace(12, 75, label: "Kannur");
        expect(rail.place, const Spot(12, 75));
        expect(rail.predict, isNull);
        expect(rail.loadingGates, isFalse);
      },
    );
  }

  test("an out-of-range saved cache timestamp cannot crash startup", () async {
    final store = DeviceStore(await SharedPreferences.getInstance());
    await store.write("responses", {
      responseKey("/gates", 12, 75): {
        "at": 9000000000000000000,
        "data": {"gates": []},
      },
    });
    final rail = RailController(_IdleApi(), storage: store);
    addTearDown(rail.dispose);
    await rail.choosePlace(12, 75, label: "Kannur");
    expect(rail.gatesCached, isFalse);
    expect(rail.loadingGates, isFalse);
  });

  test(
    "a restored location with a damaged label still loads its crossings",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.write("last-place", {"lat": 12, "lon": 75, "label": 42});
      final rail = RailController(_IdleApi(), storage: store);
      addTearDown(rail.dispose);
      await rail.restore();
      expect(rail.place, const Spot(12, 75));
      expect(rail.loadingGates, isFalse);
    },
  );

  test(
    "saved commute clocks recover safely from an unusable older value",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.write("refresh", {
        "enabled": true,
        "commute": true,
        "start": "not-a-time",
        "end": "99:99",
      });
      final settings = store.settings();
      expect(settings.start, "08:00");
      expect(settings.end, "10:00");
    },
  );
  test(
    "a granted GPS result chooses its location when no newer choice exists",
    () async {
      final rail = RailController(_IdleApi());
      addTearDown(rail.dispose);
      await rail.locate(() async => const Spot(12, 75));
      expect(rail.place, const Spot(12, 75));
      expect(rail.locating, isFalse);
      expect(rail.error, isNull);
    },
  );

  for (final denied in [false, true]) {
    test(
      "late GPS ${denied ? 'denial' : 'success'} cannot replace a newly selected city",
      () async {
        final rail = RailController(_IdleApi());
        addTearDown(rail.dispose);
        final gps = Completer<Spot>();
        final located = rail.locate(() => gps.future);
        await rail.choosePlace(13, 76, label: "New city");
        if (denied) {
          gps.completeError(StateError("Location denied"));
        } else {
          gps.complete(const Spot(12, 75));
        }
        await located;
        expect(rail.place, const Spot(13, 76));
        expect(rail.placeLabel, "New city");
        expect(rail.error, isNull);
        expect(rail.locating, isFalse);
      },
    );
  }

  test("a new map pin cancels GPS without losing the preview", () async {
    final rail = RailController(_IdleApi(), nameDelay: Duration.zero);
    addTearDown(rail.dispose);
    final gps = Completer<Spot>();
    final located = rail.locate(() => gps.future);
    rail.askPlace(13, 76);
    gps.complete(const Spot(12, 75));
    await located;
    expect(rail.pending, const Spot(13, 76));
    expect(rail.place, isNull);
    expect(rail.locating, isFalse);
    await rail.confirmPlace();
    expect(rail.place, const Spot(13, 76));
  });

  test(
    "a denied GPS request preserves the previous location and allows retry",
    () async {
      final rail = RailController(_IdleApi());
      addTearDown(rail.dispose);
      await rail.choosePlace(13, 76, label: "City before GPS");
      await rail.locate(() => Future<Spot>.error(StateError("denied")));
      expect(rail.place, const Spot(13, 76));
      expect(rail.error, contains("Location was blocked"));
      await rail.locate(() async => const Spot(12, 75));
      expect(rail.place, const Spot(12, 75));
      expect(rail.error, isNull);
    },
  );

  test("GPS completion after leaving the app does not notify a disposed controller", () async {
    final rail = RailController(_IdleApi());
    final gps = Completer<Spot>();
    final located = rail.locate(() => gps.future);
    rail.dispose();
    gps.complete(const Spot(12, 75));
    await located;
    expect(rail.place, isNull);
  });

  test(
    "a failed newer scene does not discard an older successful response",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      final replies = <Completer<http.Response>>[];
      final api = HttpRailApi(
        base: "https://example.test",
        storage: store,
        client: MockClient((_) {
          final reply = Completer<http.Response>();
          replies.add(reply);
          return reply.future;
        }),
      );
      final first = api.scene(12, 75, _gate.id);
      final second = api.scene(12, 75, _gate.id);
      await Future<void>.delayed(Duration.zero);
      final failed = expectLater(second, throwsA(isA<RailException>()));
      replies[1].complete(http.Response("unavailable", 503));
      await failed;
      replies[0].complete(
        http.Response(jsonEncode(_sceneBody("Usable first check")), 200),
      );
      await first;
      expect(
        (await api.scene(12, 75, _gate.id)).crossing!.name,
        "Usable first check",
      );
      expect(replies, hasLength(2));
    },
  );

  test(
    "invalid saved pause or location cannot prevent a fresh start",
    () async {
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.write("paused-until", 9000000000000000000);
      await store.write("last-place", {"lat": 999, "lon": 75});
      final rail = RailController(_IdleApi(), storage: store);
      addTearDown(rail.dispose);
      await rail.restore();
      expect(rail.place, isNull);
      expect(rail.paused, isFalse);
      await rail.choosePlace(12, 75, label: "Valid city");
      await rail.check();
      expect(rail.error, isNull);
    },
  );
  test("daytime and overnight commute boundaries work across a full week", () {
    for (final weekdays in [true, false]) {
      final daytime = RefreshSettings(commute: true, weekdays: weekdays);
      final overnight = RefreshSettings(
        commute: true,
        weekdays: weekdays,
        start: "22:00",
        end: "02:00",
      );
      for (var day = 16; day <= 22; day++) {
        final date = DateTime(2026, 11, day);
        final workingDay = !weekdays || date.weekday <= 5;
        final previousWorkingDay =
            !weekdays || date.subtract(const Duration(days: 1)).weekday <= 5;
        expect(daytime.allows(DateTime(2026, 11, day, 7, 59)), isFalse);
        expect(daytime.allows(DateTime(2026, 11, day, 8)), workingDay);
        expect(daytime.allows(DateTime(2026, 11, day, 9, 59)), workingDay);
        expect(daytime.allows(DateTime(2026, 11, day, 10)), isFalse);
        expect(
          overnight.allows(DateTime(2026, 11, day, 1, 59)),
          previousWorkingDay,
        );
        expect(overnight.allows(DateTime(2026, 11, day, 2)), isFalse);
        expect(overnight.allows(DateTime(2026, 11, day, 21, 59)), isFalse);
        expect(overnight.allows(DateTime(2026, 11, day, 22)), workingDay);
      }
    }
  });

  test("automatic checks respect visibility, the two-minute boundary, and server pauses", () async {
    final api = _CountingApi();
    final rail = RailController(api);
    addTearDown(rail.dispose);
    await rail.choosePlace(12, 75, label: "Kannur");
    rail.setRefresh(const RefreshSettings(enabled: true));
    await rail.autoCheck(visible: false);
    expect(api.checks, 0);
    await rail.autoCheck(visible: true);
    expect(api.checks, 1);
    rail.lastAttempt = DateTime.now().subtract(const Duration(seconds: 119));
    await rail.autoCheck(visible: true);
    expect(api.checks, 1);
    rail.lastAttempt = DateTime.now().subtract(const Duration(seconds: 121));
    await rail.autoCheck(visible: true);
    expect(api.checks, 2);
    rail.lastAttempt = DateTime.now().subtract(const Duration(minutes: 3));
    rail.pausedUntil = DateTime.now().add(const Duration(minutes: 2));
    await rail.autoCheck(visible: true);
    expect(api.checks, 2);
    await rail.check();
    expect(rail.error, contains("Checks are paused"));
  });
}

class _CountingApi extends _IdleApi {
  int checks = 0;
  @override
  Future<Predict> predict(double lat, double lon) async {
    checks++;
    return const Predict();
  }
}

class _IdleApi implements RailApi {
  @override
  Future<List<CityHit>> cities(String query) async => [];
  @override
  Future<String?> placeName(double lat, double lon) async => null;
  @override
  Future<GatesBody> gates(double lat, double lon) async =>
      const GatesBody(gates: [_gate]);
  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();
  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async =>
      const Scene(available: false);
}
