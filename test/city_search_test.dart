import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:google_fonts/google_fonts.dart";
import "package:gateahead/api.dart";
import "package:gateahead/models.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/city_search.dart";

void main() {
  testWidgets("typing a city offers a match", (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    CityHit? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: railTheme(RailColors.dark),
        home: Scaffold(
          body: CitySearch(api: _Cities(), onPick: (city) => picked = city),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), "pu");
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("Pune"), findsOneWidget);
    expect(find.text("Maharashtra"), findsOneWidget);

    await tester.tap(find.text("Pune"));
    await tester.pump();
    expect(picked?.name, "Pune");
    expect(picked?.lat, 18.52);
    expect(find.text("Pune"), findsNothing);
  });
}

class _Cities implements RailApi {
  @override
  Future<List<CityHit>> cities(String query) async {
    if (!query.toLowerCase().startsWith("pu")) return const [];
    return const [
      CityHit(name: "Pune", state: "Maharashtra", lat: 18.52, lon: 73.86),
    ];
  }

  @override
  Future<GatesBody> gates(double lat, double lon) async =>
      const GatesBody(gates: []);

  @override
  Future<String?> placeName(double lat, double lon) async => null;

  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();

  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async =>
      const Scene(available: false);
}
