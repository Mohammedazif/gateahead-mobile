import "dart:async";

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

  testWidgets("typing another city clears old options before the lookup", (
    tester,
  ) async {
    final pending = Completer<List<CityHit>>();
    CityHit? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: railTheme(RailColors.dark),
        home: Scaffold(
          body: CitySearch(
            api: _Cities(
              (query) => query == "Pune"
                  ? Future.value(const [_pune])
                  : pending.future,
            ),
            onPick: (city) => picked = city,
          ),
        ),
      ),
    );
    final input = find.byType(TextField);
    await tester.enterText(input, "Pune");
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("Pune").hitTestable(), findsWidgets);
    await tester.enterText(input, "Kochi");
    await tester.pump();
    expect(find.text("Pune"), findsNothing);
    expect(find.text("Searching cities…"), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(picked, isNull);
    pending.complete(const [
      CityHit(name: "Kochi", state: "Kerala", lat: 9.93, lon: 76.27),
    ]);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, "Kochi"));
    expect(picked?.name, "Kochi");
  });

  testWidgets("keyboard Search selects a ready match but leaves ambiguity", (
    tester,
  ) async {
    CityHit? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: railTheme(RailColors.dark),
        home: Scaffold(
          body: CitySearch(
            api: _Cities(
              (_) async => const [
                _pune,
                CityHit(
                  name: "Pune Camp",
                  state: "Maharashtra",
                  lat: 18.52,
                  lon: 73.87,
                ),
              ],
            ),
            onPick: (city) => picked = city,
          ),
        ),
      ),
    );
    final input = find.byType(TextField);
    await tester.enterText(input, "Pu");
    await tester.pump(const Duration(milliseconds: 200));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(picked, isNull);
    await tester.enterText(input, "Pune");
    await tester.pump(const Duration(milliseconds: 200));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(picked?.name, "Pune");
  });

  testWidgets("a long state fits at 276 pixels with 2.5× text", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: railTheme(RailColors.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 276,
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2.5)),
                  child: CitySearch(
                    api: _Cities(
                      (_) async => const [
                        CityHit(
                          name: "Port Blair",
                          state: "Andaman and Nicobar",
                          lat: 11.67,
                          lon: 92.74,
                        ),
                      ],
                    ),
                    onPick: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), "Port");
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("Andaman and Nicobar"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _pune = CityHit(
  name: "Pune",
  state: "Maharashtra",
  lat: 18.52,
  lon: 73.86,
);

class _Cities implements RailApi {
  _Cities([this.lookup]);
  final Future<List<CityHit>> Function(String)? lookup;

  @override
  Future<List<CityHit>> cities(String query) async {
    if (lookup != null) return lookup!(query);
    if (!query.toLowerCase().startsWith("pu")) return const [];
    return const [_pune];
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
