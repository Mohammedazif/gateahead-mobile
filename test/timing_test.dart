import "package:flutter_test/flutter_test.dart";
import "package:flutter/material.dart";
import "package:gateahead/models.dart";
import "package:gateahead/timing.dart";
import "package:gateahead/format.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/train_sheet.dart";
import "package:google_fonts/google_fonts.dart";

void main() {
  final at = DateTime.utc(2026, 11, 16, 10);
  final prediction = Predict.parse({
    "generated_at": at.toIso8601String(),
    "approaching": [
      {
        "train": "16650",
        "name": "Parasuram",
        "eta": 3,
        "age_min": 7,
        "at_station": true,
        "current": "PAZHAYANGADI",
        "ids": ["gate-a"],
        "status": "closed",
      },
      {
        "train": "16650",
        "name": "Parasuram",
        "eta": 5,
        "age_min": 7,
        "run": "at",
        "current": "PAZHAYANGADI",
        "ids": ["gate-b"],
        "status": "closing_soon",
      },
      {
        "train": "16603",
        "eta": 15,
        "age_min": 1,
        "ids": ["gate-a"],
        "status": "later",
      },
    ],
    "gate_predictions": [
      {"id": "gate-a", "train": "16650", "eta": 3, "status": "closed"},
      {"id": "gate-a", "train": "16603", "eta": 15, "status": "later"},
    ],
    "passed": [
      {"train": "16650", "ago": 3},
    ],
    "sightings": [
      {"number": "16650", "age": 7},
    ],
  });
  final scene = Scene.parse({
    "available": true,
    "_saved_at": at.millisecondsSinceEpoch,
    "crossing": {"id": "gate-a", "lat": 12, "lon": 75},
    "trains": [
      {
        "number": "16650",
        "name": "Parasuram",
        "eta_min": 3,
        "age_min": 7,
        "along_km": .5,
        "status": "closed",
        "movement": "stopped",
        "snapshot_at": at.millisecondsSinceEpoch / 1000,
        "current": "PAZHAYANGADI",
        "position_on_segment": true,
      },
      {
        "number": "16603",
        "eta_min": 15,
        "age_min": 1,
        "movement": "moving",
        "along_km": 0,
        "status": "later",
      },
    ],
    "passed": [
      {"number": "16650", "ago_min": 3},
    ],
  });

  test("a stopped prediction holds its estimate before eight minutes", () {
    final current = currentPrediction(
      prediction,
      at.add(const Duration(seconds: 59)),
    )!;
    expect(current.approaching.first.eta, 3);
    expect(current.awaitingUpdate, isEmpty);
  });

  test("stopped trains become unresolved at eight minutes without passage", () {
    final current = currentPrediction(
      prediction,
      at.add(const Duration(minutes: 1)),
    )!;
    expect(current.approaching.single.train, "16603");
    expect(current.gatePredictions!.single.train, "16603");
    expect(current.awaitingUpdate.single.number, "16650");
    expect(current.awaitingUpdate.single.current, "PAZHAYANGADI");
    expect(current.awaitingUpdate.single.ageMin, 8);
    expect(
      current.awaitingUpdate.single.ids,
      containsAll(["gate-a", "gate-b"]),
    );
    expect(current.passed, isEmpty);
    expect(lineSightings(current), isEmpty);
    expect(prediction.approaching, hasLength(3));
  });

  test(
    "crossing scene keeps stopped train unresolved alongside next service",
    () {
      final current = currentScene(scene, at.add(const Duration(minutes: 1)))!;
      expect(current.trains.single.number, "16603");
      expect(current.awaitingUpdate.single.number, "16650");
      expect(current.awaitingUpdate.single.ids, ["gate-a"]);
      expect(current.passed, isEmpty);
      expect(scene.trains, hasLength(2));
    },
  );

  test("repeated reads use the original snapshot clock", () {
    for (final minutes in [1, 2, 7]) {
      final current = currentScene(scene, at.add(Duration(minutes: minutes)))!;
      final stopped = current.awaitingUpdate.firstWhere(
        (row) => row.number == "16650",
      );
      expect(stopped.ageMin, 7 + minutes);
      if (minutes < 7) {
        expect(current.trains.single.number, "16603");
      } else {
        expect(current.trains, isEmpty);
        expect(current.awaitingUpdate.last.reason, "stale_report");
      }
    }
    expect(
      sceneReportAge(
        scene.trains.first,
        scene,
        at.add(const Duration(minutes: 1)),
      ),
      8,
    );
  });

  test(
    "offline timings retain the saved check instead of simulating travel",
    () {
      final offline = Scene(
        available: true,
        offline: true,
        savedAt: at,
        trains: scene.trains,
      );
      expect(
        identical(
          currentScene(offline, at.add(const Duration(hours: 1))),
          offline,
        ),
        isTrue,
      );
    },
  );

  test("fresh replacement moving report restores a crossing estimate", () {
    final moved = Scene.parse({
      "available": true,
      "trains": [
        {
          "number": "16650",
          "eta_min": 3,
          "age_min": 1,
          "movement": "moving",
          "along_km": 0,
          "status": "closed",
        },
      ],
    });
    expect(currentScene(moved, at)!.trains.single.number, "16650");
    expect(currentScene(moved, at)!.awaitingUpdate, isEmpty);
  });

  testWidgets(
    "an unresolved stopped train stays visible beside other services",
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final current = currentPrediction(
        prediction,
        at.add(const Duration(minutes: 1)),
      )!;
      await tester.pumpWidget(
        MaterialApp(
          theme: railTheme(RailColors.dark),
          home: Scaffold(
            body: SingleChildScrollView(child: PredictBody(predict: current)),
          ),
        ),
      );
      expect(
        find.textContaining(
          "16650 Parasuram · last reported stopped at PAZHAYANGADI",
        ),
        findsOneWidget,
      );
      expect(find.text("OTHER REPORTED TRAIN · ESTIMATE"), findsOneWidget);
      expect(find.textContaining("16603"), findsOneWidget);
      expect(find.textContaining("Recently passed"), findsNothing);
      expect(find.textContaining("No live trains reported"), findsNothing);
    },
  );

  testWidgets(
    "an inferred near crossing does not claim closure in the train list",
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final inferred = Predict.parse({
        "approaching": [
          {
            "train": "16603",
            "name": "Malabar",
            "eta": 2.3,
            "closes_in": -2.7,
            "status": "approaching",
            "ids": ["a"],
            "basis": "live",
            "bracket": "Inferred route passage",
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: railTheme(RailColors.dark),
          home: Scaffold(
            body: SingleChildScrollView(child: PredictBody(predict: inferred)),
          ),
        ),
      );
      expect(find.text("train timing uncertain"), findsOneWidget);
      expect(find.textContaining("closed ·"), findsNothing);
      expect(find.text("EST. APPROACHING"), findsOneWidget);
    },
  );
}
