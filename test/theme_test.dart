import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:google_fonts/google_fonts.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:gateahead/api.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/train_sheet.dart";

void main() {
  test("the saved choice matches the website", () async {
    SharedPreferences.setMockInitialValues({});
    expect(await RailThemeStore.read(), RailThemeMode.dark);
    await RailThemeStore.write(RailThemeMode.light);
    expect(await RailThemeStore.read(), RailThemeMode.light);
    expect(
      RailColors.light.mapStyle,
      "https://tiles.openfreemap.org/styles/positron",
    );
    expect(RailColors.light.accent, const Color(0xFF8A4E0D));
    expect(
      RailColors.dark.mapStyle,
      "https://tiles.openfreemap.org/styles/dark",
    );
    expect(RailColors.light.toggleLabel, "Dark");
    expect(RailColors.dark.toggleLabel, "Light");
  });

  testWidgets("appearance in settings switches to the light theme", (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final rail = RailController(_IdleApi());
    final scroll = ScrollController();
    addTearDown(rail.dispose);
    addTearDown(scroll.dispose);
    var mode = RailThemeMode.dark;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return RailThemeScope(
            onToggle: () {
              setState(() {
                mode = mode == RailThemeMode.light
                    ? RailThemeMode.dark
                    : RailThemeMode.light;
              });
            },
            child: MaterialApp(
              theme: railTheme(RailColors.forMode(mode)),
              themeAnimationDuration: Duration.zero,
              home: Scaffold(
                body: TrainSheet(rail: rail, onLocate: () {}, scroll: scroll),
              ),
            ),
          );
        },
      ),
    );

    expect(find.text("Light"), findsNothing);
    await tester.tap(find.byTooltip("Open settings"));
    await tester.pumpAndSettle();
    expect(find.text("Light"), findsOneWidget);
    await tester.tap(find.text("Light"));
    await tester.pumpAndSettle();
    expect(mode, RailThemeMode.light);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey("train-sheet-surface")),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, RailColors.light.sheet);
  });
}

class _IdleApi implements RailApi {
  @override
  Future<List<CityHit>> cities(String query) async => const [];

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
