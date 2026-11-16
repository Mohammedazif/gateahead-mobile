import "package:flutter_test/flutter_test.dart";
import "package:gateahead/models.dart";
import "package:gateahead/timing.dart";

void main() {
  final received = DateTime.utc(2026, 11, 16, 10);
  for (final hours in [-1, 1]) {
    final source = received.add(Duration(hours: hours));
    test(
      "prediction with server clock ${hours > 0 ? 'ahead' : 'behind'} ages from original receipt",
      () {
        final prediction = Predict.parse({
          "generated_at": source.toIso8601String(),
          "_saved_at": received.millisecondsSinceEpoch,
          "approaching": [
            {
              "train": "16650",
              "eta": 3,
              "age_min": 7,
              "status": "closed",
              "at_station": true,
              "current": "Pazhayangadi",
              "ids": ["a"],
            },
          ],
        });
        expect(
          currentPrediction(prediction, received)!.awaitingUpdate,
          isEmpty,
        );
        final after = currentPrediction(
          prediction,
          received.add(const Duration(seconds: 70)),
        )!;
        expect(after.awaitingUpdate.single.number, "16650");
        expect(after.awaitingUpdate.single.ageMin, closeTo(8 + 1 / 6, .0001));
        expect(after.approaching, isEmpty);
        final later = currentPrediction(
          prediction,
          received.add(const Duration(seconds: 140)),
        )!;
        expect(later.awaitingUpdate.single.ageMin, closeTo(9 + 1 / 3, .0001));
        expect(prediction.savedAt!.toUtc(), received);
      },
    );

    test(
      "scene with server clock ${hours > 0 ? 'ahead' : 'behind'} ages consistently with its map marker",
      () {
        final scene = Scene.parse({
          "available": true,
          "_saved_at": received.millisecondsSinceEpoch,
          "crossing": {"id": "a", "name": "School Road", "lat": 12, "lon": 75},
          "trains": [
            {
              "number": "16650",
              "eta_min": 3,
              "age_min": 7,
              "movement": "stopped",
              "current": "Pazhayangadi",
              "snapshot_at": source.millisecondsSinceEpoch / 1000,
            },
          ],
        });
        expect(currentScene(scene, received)!.awaitingUpdate, isEmpty);
        expect(sceneReportAge(scene.trains.single, scene, received), 7);
        final after = currentScene(
          scene,
          received.add(const Duration(seconds: 70)),
        )!;
        expect(after.awaitingUpdate.single.number, "16650");
        expect(after.trains, isEmpty);
        expect(after.passed, isEmpty);
        expect(
          sceneReportAge(
            scene.trains.single,
            scene,
            received.add(const Duration(seconds: 70)),
          ),
          closeTo(8 + 1 / 6, .0001),
        );
        expect(
          currentScene(
            scene,
            received.add(const Duration(seconds: 140)),
          )!.awaitingUpdate.single.ageMin,
          closeTo(9 + 1 / 3, .0001),
        );
      },
    );
  }

  test("a plausible cached source clock keeps the original elapsed time", () {
    final source = received.subtract(const Duration(seconds: 90));
    final scene = Scene.parse({
      "available": true,
      "_saved_at": received.millisecondsSinceEpoch,
      "trains": [
        {
          "number": "16650",
          "eta_min": 3,
          "age_min": 7,
          "movement": "stopped",
          "snapshot_at": source.millisecondsSinceEpoch / 1000,
        },
      ],
    });
    expect(sceneReportAge(scene.trains.single, scene, received), 8.5);
    expect(
      currentScene(scene, received)!.awaitingUpdate.single.number,
      "16650",
    );
  });

  test("legacy scenes without receipt metadata retain their source clock", () {
    final scene = Scene.parse({
      "available": true,
      "trains": [
        {
          "number": "16650",
          "eta_min": 3,
          "age_min": 7,
          "movement": "stopped",
          "snapshot_at": received.millisecondsSinceEpoch / 1000,
        },
      ],
    });
    expect(
      sceneReportAge(
        scene.trains.single,
        scene,
        received.add(const Duration(seconds: 70)),
      ),
      closeTo(8 + 1 / 6, .0001),
    );
  });
}
