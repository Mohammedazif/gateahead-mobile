import "package:flutter_test/flutter_test.dart";
import "package:gateahead/format.dart";
import "package:gateahead/models.dart";

void main() {
  test("friendly errors stay short", () {
    expect(friendlyError("map_busy"), "The crossing list is busy. Wait a minute and try again.");
    expect(friendlyError("crossing_not_found"), "That crossing is no longer on the map.");
    expect(friendlyError("overpass down"), "The crossing list did not load. Try again in a minute.");
    expect(friendlyError(null), "Something went wrong. Try again in a moment.");
  });

  test("place names and closing times match the web copy", () {
    expect(cleanPlace("MANGALORE CNTL ~ JN"), "Mangalore Central Jn");
    expect(etaLabel(0.4), "closing now");
    expect(etaLabel(8), "closes in 8 min");
    expect(etaLabel(90), "closes in 1 hr 30 min");
    final at = DateTime(2026, 11, 13, 1, 0);
    expect(checkedAgo(at, at.add(const Duration(seconds: 20))), "Checked just now");
    expect(checkedAgo(at, at.add(const Duration(minutes: 4))), "Checked 4 min ago");
    expect(checkedAgo(at, at.add(const Duration(minutes: 90))), "Checked 1 hr 30 min ago");
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
      const Gate(id: "near", name: "Near", lat: 1, lon: 1, km: 0.2, source: "osm"),
      const Gate(id: "hot", name: "Hot", lat: 1, lon: 1, km: 1.2, source: "osm"),
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
    expect(marked.firstWhere((gate) => gate.id == "hot").name, "Payyanur gates");
    expect(shownGates(marked).first.id, "hot");
    expect(lineSightings(predict), isEmpty);
  });
}
