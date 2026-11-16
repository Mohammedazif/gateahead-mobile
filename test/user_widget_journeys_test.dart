import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:google_fonts/google_fonts.dart";
import "package:gateahead/api.dart";
import "package:gateahead/device_store.dart";
import "package:gateahead/models.dart";
import "package:gateahead/rail_controller.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/city_search.dart";
import "package:gateahead/ui/train_sheet.dart";

const _gate = Gate(
  id: "school",
  name: "School Road",
  lat: 12,
  lon: 75,
  km: 0.4,
  source: "osm",
);

Future<void> _pumpSheet(WidgetTester tester, RailController rail) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
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
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final fail in [false, true]) {
    testWidgets(
      "clearing city search suppresses late ${fail ? 'failure' : 'matches'}",
      (tester) async {
        final api = _JourneyApi();
        final result = Completer<List<CityHit>>();
        api.cityReply = result;
        await tester.pumpWidget(
          MaterialApp(
            theme: railTheme(RailColors.dark),
            home: Scaffold(
              body: CitySearch(api: api, onPick: (_) {}),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), "Kannur");
        await tester.pump(const Duration(milliseconds: 200));
        await tester.enterText(find.byType(TextField), "");
        if (fail) {
          result.completeError(StateError("slow failed query"));
        } else {
          result.complete(const [
            CityHit(name: "Kannur", state: "Kerala", lat: 12, lon: 75),
          ]);
        }
        await tester.pump();
        expect(find.text("Kannur"), findsNothing);
        expect(find.text("City search did not load."), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets("a commuter saves, renames, reopens and removes a crossing", (
    tester,
  ) async {
    final rail = RailController(_JourneyApi());
    addTearDown(rail.dispose);
    await rail.choosePlace(12, 75, label: "Kannur");
    await _pumpSheet(tester, rail);
    await _tap(tester, find.text("School Road"));
    await _tap(tester, find.text("Save gate"));
    await tester.enterText(find.byType(TextField), "Home gate");
    await _tap(tester, find.text("Save"));
    expect(rail.favorites.single.label, "Home gate");
    await _tap(tester, find.text("Saved"));
    await _tap(tester, find.byTooltip("Manage Home gate"));
    await _tap(tester, find.text("Rename"));
    await tester.enterText(find.byType(TextField), "Work gate");
    await _tap(tester, find.text("Save"));
    expect(rail.favorites.single.label, "Work gate");
    await _tap(tester, find.text("Work gate"));
    expect(rail.selected?.id, _gate.id);
    await _tap(tester, find.text("Back to crossings"));
    await _tap(tester, find.text("Saved"));
    await _tap(tester, find.byTooltip("Manage Work gate"));
    await _tap(tester, find.text("Remove"));
    expect(rail.favorites, isEmpty);
    expect(find.text("Your regular crossings, together"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("sharing a gate copies a usable crossing link", (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == "Clipboard.setData") {
          copied = (call.arguments as Map)["text"] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final rail = RailController(_JourneyApi());
    addTearDown(rail.dispose);
    await rail.choosePlace(12, 75, label: "Kannur");
    await rail.openGate(_gate);
    await _pumpSheet(tester, rail);
    await _tap(tester, find.text("Share"));
    expect(parseCrossingLink(copied!)?.gateId, _gate.id);
    expect(parseCrossingLink(copied!)?.place, _gate.spot);
    expect(find.text("Crossing link copied."), findsOneWidget);
  });

  testWidgets(
    "reporting allows retry after failure without closing the selected crossing",
    (tester) async {
      final api = _JourneyApi()..failReport = true;
      final rail = RailController(api);
      addTearDown(rail.dispose);
      await rail.choosePlace(12, 75, label: "Kannur");
      await rail.openGate(_gate);
      await _pumpSheet(tester, rail);
      await _tap(tester, find.text("Report"));
      await _tap(tester, find.text("The gate is closed"));
      expect(
        find.text("Could not send your report. Try again later."),
        findsOneWidget,
      );
      expect(rail.selected?.id, _gate.id);
      api.failReport = false;
      await _tap(tester, find.text("The gate is open"));
      expect(api.reportStates, ["closed", "open"]);
      expect(find.text("Report this crossing"), findsNothing);
      expect(find.text("Report saved for 10 minutes."), findsOneWidget);
      expect(rail.selected?.id, _gate.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    "dismissing a pending report cannot pop the crossing when its reply arrives",
    (tester) async {
      final api = _JourneyApi()
        ..reportReply = Completer<List<Map<String, dynamic>>>();
      final rail = RailController(api);
      addTearDown(rail.dispose);
      await rail.choosePlace(12, 75, label: "Kannur");
      await rail.openGate(_gate);
      await _pumpSheet(tester, rail);
      await _tap(tester, find.text("Report"));
      await _tap(tester, find.text("The gate is closed"));
      expect(find.text("Sending report…"), findsOneWidget);
      await _tap(tester, find.byTooltip("Close report"));
      api.reportReply!.complete([]);
      await tester.pumpAndSettle();
      expect(rail.selected?.id, _gate.id);
      expect(find.text("Back to crossings"), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final hasKnownTrain in [false, true]) {
    testWidgets(
      "discovery failure is visible ${hasKnownTrain ? 'beside known services' : 'without estimates'}",
      (tester) async {
        final prediction = Predict.parse({
          "coverage": {"unavailable_discovery": 2},
          "approaching": hasKnownTrain
              ? [
                  {
                    "train": "16650",
                    "name": "Parasuram",
                    "eta": 12,
                    "status": "approaching",
                    "ids": ["school"],
                    "current": "Kannur",
                  },
                ]
              : [],
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: railTheme(RailColors.dark),
            home: Scaffold(
              body: SingleChildScrollView(
                child: PredictBody(predict: prediction),
              ),
            ),
          ),
        );
        expect(
          find.textContaining("Train discovery could not complete"),
          findsOneWidget,
        );
        if (hasKnownTrain) expect(find.textContaining("16650"), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    "commute settings stay disabled before a place and allow safe time selection afterward",
    (tester) async {
      final rail = RailController(_JourneyApi());
      addTearDown(rail.dispose);
      await _pumpSheet(tester, rail);
      await _tap(tester, find.byTooltip("Open settings"));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await _tap(tester, find.byTooltip("Close settings"));
      await rail.choosePlace(12, 75, label: "Kannur");
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip("Open settings"));
      await _tap(tester, find.text("Check every 2 minutes"));
      await _tap(tester, find.text("Only during my commute"));
      await tester.drag(find.byType(ListView).last, const Offset(0, -250));
      await tester.pumpAndSettle();
      await _tap(tester, find.text("From 08:00"));
      await _tap(tester, find.text("Cancel"));
      expect(rail.refresh.enabled, isTrue);
      expect(rail.refresh.commute, isTrue);
      expect(rail.refresh.start, "08:00");
      expect(tester.takeException(), isNull);
    },
  );
}

class _JourneyApi implements RailApi, CommunityApi {
  Completer<List<CityHit>>? cityReply;
  Completer<List<Map<String, dynamic>>>? reportReply;
  bool failReport = false;
  final reportStates = <String>[];
  @override
  Future<List<CityHit>> cities(String query) async =>
      cityReply == null ? [] : cityReply!.future;
  @override
  Future<String?> placeName(double lat, double lon) async => null;
  @override
  Future<GatesBody> gates(double lat, double lon) async =>
      const GatesBody(gates: [_gate]);
  @override
  Future<Predict> predict(double lat, double lon) async => const Predict();
  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async =>
      const Scene(
        available: true,
        crossing: SceneCrossing(
          id: "school",
          name: "School Road",
          lat: 12,
          lon: 75,
        ),
        rail: [Spot(11.99, 75), Spot(12.01, 75)],
      );
  @override
  Future<List<Map<String, dynamic>>> reports(String id) async => [];
  @override
  Future<List<Map<String, dynamic>>> report(Gate gate, String state) async {
    reportStates.add(state);
    if (failReport) throw RailException("Failed report");
    if (reportReply != null) return reportReply!.future;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return [
      {"state": state, "at": now, "expires_at": now + 600},
    ];
  }
}
