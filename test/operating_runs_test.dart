import "package:flutter_test/flutter_test.dart";
import "package:flutter/material.dart";
import "package:gateahead/theme.dart";
import "package:gateahead/ui/train_sheet.dart";
import "package:google_fonts/google_fonts.dart";
import "package:gateahead/device_store.dart";
import "package:gateahead/format.dart";
import "package:gateahead/models.dart";
import "package:gateahead/timing.dart";

void main() {
  final at = DateTime.utc(2026, 11, 16, 10);
  const oldId = "16512:2026-11-15";
  const newId = "16512:2026-11-16";
  final prediction = Predict.parse({
    "_saved_at": at.millisecondsSinceEpoch,
    "approaching": [
      {
        "train": "16512",
        "run_id": oldId,
        "start_date": "2026-11-15",
        "eta": 3,
        "age_min": 7,
        "at_station": true,
        "current": "South",
        "status": "closed",
        "ids": ["gate"],
      },
      {
        "train": "16512",
        "run_id": newId,
        "start_date": "2026-11-16",
        "eta": 5,
        "age_min": 1,
        "status": "closing_soon",
        "ids": ["gate"],
      },
    ],
    "gate_predictions": [
      {
        "id": "gate",
        "train": "16512",
        "run_id": oldId,
        "eta": 3,
        "status": "closed",
      },
      {
        "id": "gate",
        "train": "16512",
        "run_id": newId,
        "eta": 5,
        "status": "closing_soon",
      },
    ],
  });
  final scene = Scene.parse({
    "available": true,
    "_saved_at": at.millisecondsSinceEpoch,
    "crossing": {"id": "gate", "lat": 12.01, "lon": 75},
    "trains": [
      {
        "number": "16512",
        "run_id": oldId,
        "start_date": "2026-11-15",
        "eta_min": 3,
        "age_min": 7,
        "movement": "stopped",
        "current": "South",
        "status": "closed",
      },
      {
        "number": "16512",
        "run_id": newId,
        "start_date": "2026-11-16",
        "eta_min": 5,
        "age_min": 1,
        "movement": "moving",
        "status": "closing_soon",
      },
    ],
  });

  test("two origin dates of one service remain separate in the train list", () {
    expect(groupApproaches(prediction.approaching).keys, [oldId, newId]);
  });

  test(
    "a stale stopped journey does not remove the next day's moving service",
    () {
      final now = at.add(const Duration(minutes: 1));
      final current = currentPrediction(prediction, now)!;
      expect(current.approaching.single.identity, newId);
      expect(current.awaitingUpdate.single.identity, oldId);
      final gateCheck = currentScene(scene, now)!;
      expect(gateCheck.trains.single.identity, newId);
      expect(gateCheck.awaitingUpdate.single.identity, oldId);
      final merged = withGateChecks(current, [gateCheck], [])!;
      expect(merged.approaching.single.identity, newId);
      expect(merged.awaitingUpdate.single.identity, oldId);
      expect(merged.gatePredictions!.single.identity, newId);
    },
  );

  test(
    "a newer cancellation removes the affected run without hiding its sibling",
    () {
      final check = Scene.parse({
        "available": true,
        "_saved_at": at.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
        "crossing": {"id": "gate", "lat": 12.01, "lon": 75},
        "trains": [
          {
            "number": "16512",
            "run_id": newId,
            "start_date": "2026-11-16",
            "eta_min": 5,
            "age_min": 1,
            "movement": "moving",
            "status": "closing_soon",
          },
        ],
        "service_updates": [
          {
            "number": "16512",
            "start_date": "2026-11-15",
            "status": "cancelled",
          },
        ],
      });
      final merged = withGateChecks(prediction, [check], [])!;
      expect(merged.approaching.single.identity, newId);
      expect(merged.serviceUpdates.single.identity, oldId);
      expect(
        currentPrediction(
          merged,
          at.add(const Duration(minutes: 1)),
        )!.serviceUpdates.single.status,
        "cancelled",
      );
    },
  );

  test("invalid operating update containers are rejected before rendering", () {
    expect(
      validResponseBody("/predict", {
        "approaching": [],
        "service_updates": "broken",
      }),
      isFalse,
    );
    expect(
      validResponseBody("/predict", {
        "approaching": [],
        "service_updates": [
          {"number": "16512", "status": "made_up"},
        ],
      }),
      isFalse,
    );
    expect(
      validResponseBody("/predict", {
        "approaching": [],
        "service_updates": [
          {"number": "16512", "status": "diverted", "start_date": "2026-11-16"},
        ],
      }),
      isTrue,
    );
  });
  testWidgets(
    "origin dates distinguish train cards without exposing internal run keys",
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
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
      expect(find.textContaining("16512:2026"), findsNothing);
      expect(find.textContaining("Started 2026-11-15"), findsOneWidget);
      expect(find.textContaining("Started 2026-11-16"), findsOneWidget);
    },
  );

  testWidgets(
    "operating exceptions show journey dates without a closure countdown",
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final updates = Predict.parse({
        "approaching": [],
        "service_updates": [
          {"number": "16512", "start_date": "2026-11-15", "status": "diverted"},
          {
            "number": "16512",
            "start_date": "2026-11-16",
            "status": "cancelled",
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: railTheme(RailColors.dark),
          home: Scaffold(
            body: SingleChildScrollView(child: PredictBody(predict: updates)),
          ),
        ),
      );
      expect(
        find.textContaining("Started 2026-11-15 · Diverted"),
        findsOneWidget,
      );
      expect(
        find.textContaining("Started 2026-11-16 · Cancelled"),
        findsOneWidget,
      );
      expect(find.textContaining("until this journey"), findsOneWidget);
      expect(find.textContaining("closes in"), findsNothing);
      expect(find.textContaining("No live trains reported"), findsNothing);
    },
  );
}
