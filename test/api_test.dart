import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:gateahead/api.dart";
import "package:gateahead/geo.dart";
import "package:gateahead/models.dart";

void main() {
  test("gate and scene payloads use the FastAPI paths", () async {
    final seen = <String>[];
    final api = HttpRailApi(
      base: "http://127.0.0.1:8000/",
      client: MockClient((request) async {
        seen.add("${request.url.path}?${request.url.query}");
        if (request.url.path == "/gates") {
          return http.Response(
            '{"gates":[{"id":"n1","name":"LC 42","lat":12.1,"lon":75.2,"km":0.4,"source":"osm"}]}',
            200,
          );
        }
        return http.Response(
          '{"available":true,"crossing":{"id":"n1","name":"LC 42","lat":12.1,"lon":75.2},"rail":[[12.0,75.2],[12.2,75.2]],"trains":[{"number":"16604","name":"Maveli","eta_min":4.2,"status":"closing_soon","along_km":0.4,"age_min":2}]}',
          200,
        );
      }),
    );

    final gates = await api.gates(12.1, 75.2);
    expect(gates.gates.single.name, "LC 42");
    final scene = await api.scene(12.1, 75.2, "n1");
    expect(scene.available, isTrue);
    expect(scene.rail, [const Spot(12, 75.2), const Spot(12.2, 75.2)]);
    expect(scene.trains.single.etaMin, 4.2);
    expect(seen, [
      "/gates?lat=12.1&lon=75.2",
      "/scene?lat=12.1&lon=75.2&crossing_id=n1",
    ]);
  });

  test("a busy predict tells the person to wait", () async {
    final api = HttpRailApi(
      base: "http://10.0.2.2:8000",
      client: MockClient((request) async => http.Response("slow", 429)),
    );
    expect(
      api.predict(12, 75),
      throwsA(
        isA<RailException>().having(
          (err) => err.message,
          "message",
          "Too many checks. Wait a few minutes and try again.",
        ),
      ),
    );
  });

  test("predict keeps an approaching train and drops a passed sighting", () {
    final predict = Predict.parse({
      "crossings": 3,
      "stations": ["PAY", "KGQ"],
      "checked": 4,
      "running": 1,
      "approaching": [
        {
          "train": "16312",
          "name": "Vanchinad",
          "cluster": "Near Payyanur",
          "count": 2,
          "eta": 9.5,
          "status": "closing_soon",
          "at_station": false,
          "current": "KANNUR",
          "from_you_km": 1.1,
          "lat": 12.1,
          "lon": 75.2,
          "ids": ["a", "b"],
          "origin": "MANGALORE JN",
          "dest": "TRIVANDRUM CNTL",
          "run": "departed",
          "departed_at": "18:10",
        },
      ],
      "sightings": [
        {"number": "16312", "name": "Vanchinad", "current": "KANNUR", "delay": 4, "age": 3, "passed_local": false},
        {"number": "16604", "name": "Maveli", "current": "KASARAGOD", "delay": 0, "age": 50, "passed_local": false},
      ],
    });
    expect(predict.approaching.single.ids, ["a", "b"]);
    expect(predict.approaching.single.runInfo.origin, "MANGALORE JN");
    expect(predict.sightings, hasLength(2));
  });

  test("a train sits on the rail at its along-track kilometre", () {
    final line = [const Spot(12, 75), const Spot(12.01, 75)];
    final at = pointAlongKm(line, kmBetween(line.first, line.last) / 2);
    expect(at.lat, closeTo(12.005, 0.0002));
    expect(at.lon, closeTo(75, 0.0002));
    expect(pointAlongKm(line, 99).lat, closeTo(12.01, 0.0001));
  });
}
