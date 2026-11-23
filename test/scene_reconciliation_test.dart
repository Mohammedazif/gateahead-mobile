import "package:flutter_test/flutter_test.dart";
import "package:gateahead/api.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";

const _a = Gate(
  id: "a",
  name: "School Road",
  lat: 12,
  lon: 75,
  km: 0.2,
  source: "osm",
);
const _b = Gate(
  id: "b",
  name: "Market Road",
  lat: 12.01,
  lon: 75,
  km: 0.5,
  source: "osm",
);

Predict _prediction(
  DateTime at, {
  String status = "closed",
  bool awaiting = false,
}) => Predict.parse({
  "_saved_at": at.millisecondsSinceEpoch,
  "approaching": awaiting
      ? []
      : [
          {
            "train": "16650",
            "name": "Parasuram",
            "eta": 3,
            "status": status,
            "ids": ["a", "b"],
            "current": "Kannur",
          },
        ],
  "gate_predictions": awaiting
      ? []
      : [
          {
            "id": "a",
            "train": "16650",
            "eta": 3,
            "closes_in": -2,
            "status": status,
          },
          {
            "id": "b",
            "train": "16650",
            "eta": 6,
            "closes_in": 1,
            "status": "closing_soon",
          },
        ],
  "awaiting_update": awaiting
      ? [
          {
            "number": "16650",
            "name": "Parasuram",
            "current": "PAZHAYANGADI",
            "age_min": 14,
            "ids": ["a", "b"],
          },
        ]
      : [],
});

Scene _scene(
  DateTime at, {
  String id = "a",
  bool awaiting = false,
  bool offline = false,
  bool empty = false,
}) => Scene.parse({
  "available": true,
  "_saved_at": at.millisecondsSinceEpoch,
  "_offline": offline,
  "crossing": {
    "id": id,
    "name": id == "a" ? _a.name : _b.name,
    "lat": 12,
    "lon": 75,
  },
  "rail": [
    [12, 75],
    [12.01, 75],
  ],
  "trains": empty
      ? []
      : [
          {
            "number": "16603",
            "name": "Malabar",
            "eta_min": 12,
            "along_km": .5,
            "closes_in_min": 7,
            "status": "approaching",
            "age_min": 1,
            "movement": "moving",
            "basis": "live",
          },
        ],
  "awaiting_update": awaiting
      ? [
          {
            "number": "16650",
            "name": "Parasuram",
            "current": "PAZHAYANGADI",
            "age_min": 14,
            "ids": [id],
          },
        ]
      : [],
});

void main() {
  late DateTime now;
  late _Api api;
  late RailController rail;
  setUp(() async {
    now = DateTime.now();
    api = _Api();
    rail = RailController(api);
    await rail.choosePlace(12, 75, label: "Kannur");
    rail.predict = _prediction(now.subtract(const Duration(minutes: 1)));
  });
  tearDown(() => rail.dispose());

  test("returning Nearby retains the newer gate scene and its train", () async {
    api.nextScene = _scene(now);
    await rail.openGate(_a);
    rail.closeScene();
    expect(rail.markedGates.first.status, "approaching");
    expect(rail.markedGates.first.eta, 12);
    expect(rail.markedGates.last.status, "closing_soon");
    final oldTrain = rail.predict!.approaching
        .where((row) => row.train == "16650")
        .single;
    expect(oldTrain.ids, ["b"]);
    expect(oldTrain.eta, 6);
    final newTrain = rail.predict!.approaching
        .where((row) => row.train == "16603")
        .single;
    expect(newTrain.ids, ["a"]);
    expect(newTrain.eta, 12);
  });

  test(
    "a newer stopped report remains unresolved beside another service",
    () async {
      api.nextScene = _scene(now, awaiting: true);
      await rail.openGate(_a);
      rail.closeScene();
      expect(rail.markedGates.first.status, "uncertain");
      expect(rail.markedGates.first.eta, isNull);
      expect(rail.markedGates.last.status, "closing_soon");
      expect(rail.predict!.awaitingUpdate.single.ids, ["a"]);
      expect(rail.predict!.awaitingUpdate.single.number, "16650");
      expect(
        rail.predict!.approaching.any(
          (row) => row.train == "16603" && row.ids.contains("a"),
        ),
        isTrue,
      );
      expect(
        rail.predict!.approaching.any(
          (row) => row.train == "16650" && row.ids.contains("a"),
        ),
        isFalse,
      );
    },
  );

  test("a newer nearby check supersedes a retained gate scene", () async {
    api.nextScene = _scene(now, awaiting: true);
    await rail.openGate(_a);
    rail.predict = _prediction(now.add(const Duration(seconds: 1)));
    rail.closeScene();
    expect(rail.markedGates.first.status, "closed");
    expect(rail.predict!.awaitingUpdate, isEmpty);
    expect(rail.predict!.approaching.single.train, "16650");
  });

  for (final offline in [false, true]) {
    test(
      "${offline ? 'offline' : 'older cached'} scenes do not overwrite a newer prediction",
      () async {
        api.nextScene = _scene(
          offline ? now : now.subtract(const Duration(minutes: 2)),
          awaiting: true,
          offline: offline,
        );
        await rail.openGate(_a);
        rail.closeScene();
        expect(rail.markedGates.first.status, "closed");
        expect(rail.predict!.awaitingUpdate, isEmpty);
        expect(rail.predict!.approaching.single.train, "16650");
      },
    );
  }

  test("changing place clears every retained gate check", () async {
    api.nextScene = _scene(now, awaiting: true);
    await rail.openGate(_a);
    await rail.choosePlace(13, 76, label: "New place");
    expect(rail.gateChecks, isEmpty);
    expect(rail.markedGates.first.status, isNull);
    expect(rail.predict, isNull);
  });

  test("a resolved gate does not clear uncertainty at another gate", () async {
    rail.predict = _prediction(
      now.subtract(const Duration(minutes: 1)),
      awaiting: true,
    );
    api.nextScene = _scene(now);
    await rail.openGate(_a);
    rail.closeScene();
    expect(rail.predict!.awaitingUpdate.single.ids, ["b"]);
    expect(rail.markedGates.first.status, "approaching");
    expect(rail.markedGates.last.status, "uncertain");
  });

  test("a scene can mark a gate before the first nearby train check", () async {
    rail.predict = null;
    api.nextScene = _scene(now);
    await rail.openGate(_a);
    rail.closeScene();
    expect(rail.markedGates.first.status, "approaching");
    expect(rail.markedGates.last.status, isNull);
  });

  test("a newly cleared scene removes a stale closed estimate", () async {
    api.nextScene = _scene(now, empty: true);
    await rail.openGate(_a);
    rail.closeScene();
    expect(rail.markedGates.first.status, isNull);
    expect(rail.predict!.approaching.single.ids, ["b"]);
  });

  test("per-gate checks survive opening and closing another gate", () async {
    api.nextScene = _scene(now, awaiting: true);
    await rail.openGate(_a);
    api.nextScene = _scene(now, id: "b");
    await rail.openGate(_b);
    rail.closeScene();
    expect(rail.gateChecks, hasLength(2));
    expect(rail.markedGates.first.status, "uncertain");
    expect(rail.markedGates.last.status, "approaching");
    expect(rail.predict!.awaitingUpdate.single.ids, ["a"]);
    expect(
      rail.predict!.approaching.every((row) => row.train == "16603"),
      isTrue,
    );
  });
}

class _Api implements RailApi {
  Scene nextScene = const Scene(available: false);
  @override
  Future<List<CityHit>> cities(String query) async => [];
  @override
  Future<String?> placeName(double lat, double lon) async => null;
  @override
  Future<GatesBody> gates(double lat, double lon) async =>
      const GatesBody(gates: [_a, _b]);
  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();
  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async =>
      nextScene;
}
