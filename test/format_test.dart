import "package:flutter_test/flutter_test.dart";
import "package:gateahead/format.dart";
import "package:gateahead/models.dart";

void main() {
  test("friendly errors stay short", () {
    expect(
      friendlyError("map_busy"),
      "The crossing list is busy. Wait a minute and try again.",
    );
    expect(
      friendlyError("crossing_not_found"),
      "That crossing is no longer on the map.",
    );
    expect(
      friendlyError("overpass down"),
      "The crossing list did not load. Try again in a minute.",
    );
    expect(friendlyError(null), "Something went wrong. Try again in a moment.");
  });

  test("place names and closing times match the web copy", () {
    expect(cleanPlace("MANGALORE CNTL ~ JN"), "Mangalore Central Jn");
    expect(gateLabel(0.4), "closing now");
    expect(gateLabel(8), "closes in 8 min");
    expect(gateLabel(95, 90), "closes in 1 hr 30 min");
    final at = DateTime(2026, 11, 13, 1, 0);
    expect(
      checkedAgo(at, at.add(const Duration(seconds: 20))),
      "Checked just now",
    );
    expect(
      checkedAgo(at, at.add(const Duration(minutes: 4))),
      "Checked 4 min ago",
    );
    expect(
      checkedAgo(at, at.add(const Duration(minutes: 90))),
      "Checked 1 hr 30 min ago",
    );
    expect(delayLabel(12), "12 min late");
    expect(delayLabel(-3), "3 min early");
    expect(labelStatus("closing_soon"), "Closing");
  });

  test("a departed train keeps the platform and the next halt", () {
    final copy = runCopy(
      const RunInfo(
        current: "KANNUR",
        origin: "MANGALORE CNTL",
        dest: "TRIVANDRUM CNTL",
        nextStop: "PAYYANNUR",
        nextIn: "14 min",
        departedAt: "16:02",
        platform: "1",
        leftKm: 42,
        run: "departed",
        delay: 6,
      ),
      showDelay: true,
    );
    expect(copy.route, "Mangalore Central to Trivandrum Central");
    expect(copy.place, "Departed Kannur at 16:02, platform 1");
    expect(copy.delay, "6 min late");
    expect(copy.next, "Next Payyannur · 14 min · 42 km left");
  });

  test("closing gates sort ahead of the rest", () {
    final gates = [
      const Gate(id: "far", name: "Far", lat: 1, lon: 1, km: 4, source: "osm"),
      const Gate(
        id: "near",
        name: "Near",
        lat: 1,
        lon: 1,
        km: 0.2,
        source: "osm",
      ),
      const Gate(
        id: "hot",
        name: "Hot",
        lat: 1,
        lon: 1,
        km: 1.2,
        source: "osm",
      ),
    ];
    final predict = Predict(
      approaching: [
        Approach(
          train: "16312",
          name: "Vanchinad",
          cluster: "Payyanur gates",
          count: 1,
          eta: 6,
          status: "closing_soon",
          fromYouKm: 1.2,
          lat: 1,
          lon: 1,
          ids: const ["hot"],
          runInfo: const RunInfo(),
        ),
      ],
    );
    final marked = markGates(gates, predict);
    expect(marked.firstWhere((gate) => gate.id == "hot").name, "Hot");
    expect(shownGates(marked).first.id, "hot");
    expect(lineSightings(predict), isEmpty);
  });

  test("the label counts down to the barrier, not the train", () {
    expect(gateLabel(12, 7), "closes in 7 min");
    expect(gateLabel(5.6, 0.6), "closing now");
    expect(gateLabel(4, -1), "closed · train in 4 min");
    expect(gateLabel(0.5, -4.5), "closed · train due within 1 min");
    expect(gateLabel(119.8, 119.8), "closes in 2 hr");
    expect(passedLabel(0.4), "passed just now");
    expect(passedLabel(2.6), "passed 3 min ago");
    expect(labelStatus("passed"), "Passed");
  });

  test(
    "an uncertain inferred approach cannot claim that the barrier is closed",
    () {
      expect(gateLabel(2.3, -2.7, "approaching"), "train timing uncertain");
      expect(gateLabel(0.5, -4.5, "approaching"), "train timing uncertain");
      expect(gateLabel(4, -1, "closed"), "closed · train in 4 min");
      expect(gateLabel(0, -5, "closed"), "closed · train passing");
      expect(gateLabel(0.5, -4.5, "closed"), "closed · train due within 1 min");
      expect(gateLabel(4, -1), "closed · train in 4 min");
    },
  );

  test(
    "a just-passed train is listed once and the gate keeps its barrier time",
    () {
      final predict = Predict.parse({
        "approaching": [
          {
            "train": "16603",
            "name": "Malabar",
            "cluster": "School Road",
            "eta": 9,
            "closes_in": 4,
            "status": "closing_soon",
            "ids": ["g1"],
          },
        ],
        "passed": [
          {
            "train": "16601",
            "name": "Coastal",
            "cluster": "School Road",
            "ago": 1.4,
            "ids": ["g1"],
          },
        ],
        "sightings": [
          {
            "number": "16601",
            "name": "Coastal",
            "age": 1,
            "passed_local": false,
          },
        ],
      });
      expect(predict.passed.single.train, "16601");
      expect(predict.passed.single.ago, 1.4);
      expect(predict.approaching.single.closesIn, 4);
      expect(lineSightings(predict), isEmpty);
      final marked = markGates([
        const Gate(
          id: "g1",
          name: "LC",
          lat: 1,
          lon: 1,
          km: 0.1,
          source: "osm",
        ),
      ], predict);
      expect(marked.single.closesIn, 4);
      expect(
        gateLabel(marked.single.eta!, marked.single.closesIn),
        "closes in 4 min",
      );
    },
  );

  test("the gate view reads the barrier time and a passed train", () {
    final scene = Scene.parse({
      "available": true,
      "rail": [
        [12.0, 75.2],
        [12.2, 75.2],
      ],
      "trains": [
        {
          "number": "16603",
          "name": "Malabar",
          "eta_min": 4.2,
          "closes_in_min": -0.8,
          "status": "closed",
          "along_km": 0.4,
          "age_min": 2,
        },
      ],
      "passed": [
        {"number": "16601", "name": "Coastal", "ago_min": 2.2},
      ],
    });
    expect(scene.trains.single.closesInMin, -0.8);
    expect(scene.passed.single.number, "16601");
    expect(
      gateLabel(scene.trains.single.etaMin, scene.trains.single.closesInMin),
      "closed · train in 4 min",
    );
    final older = Scene.parse({"available": true, "rail": [], "trains": []});
    expect(older.passed, isEmpty);
  });
}
