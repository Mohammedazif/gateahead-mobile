import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:google_fonts/google_fonts.dart";
import "package:gateahead/api.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/train_sheet.dart";

void main() {
  testWidgets("the selected location appears beside its crossing count", (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final rail = RailController(_LocationApi());
    final scroll = ScrollController();
    addTearDown(rail.dispose);
    addTearDown(scroll.dispose);
    await rail.choosePlace(12, 75);
    await tester.pumpWidget(
      RailThemeScope(
        onToggle: () {},
        child: MaterialApp(
          theme: railTheme(RailColors.dark),
          home: Scaffold(
            body: TrainSheet(rail: rail, onLocate: () {}, scroll: scroll),
          ),
        ),
      ),
    );
    expect(find.text("Kannur · 19 crossings on this map."), findsOneWidget);
  });
}

class _LocationApi implements RailApi {
  @override
  Future<List<CityHit>> cities(String query) async => const [];

  @override
  Future<String?> placeName(double lat, double lon) async => "Kannur";

  @override
  Future<GatesBody> gates(double lat, double lon) async => GatesBody(
    gates: List.generate(
      19,
      (index) => Gate(
        id: "$index",
        name: "Crossing $index",
        lat: lat,
        lon: lon,
        km: index.toDouble(),
        source: "osm",
      ),
    ),
  );

  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();

  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async =>
      const Scene(available: false);
}
