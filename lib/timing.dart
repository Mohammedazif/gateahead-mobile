import "models.dart";

// Keep plausible source timing, but do not mix an offset server clock with
// this device's clock. Cached reads retain their original receipt timestamp.
DateTime? _anchor(DateTime? source, DateTime? received) {
  if (source == null) return received;
  if (received == null) return source;
  final delay = received.difference(source);
  return delay >= Duration.zero && delay <= const Duration(seconds: 120)
      ? source
      : received;
}

double _elapsedMinutes(DateTime? at, DateTime now) =>
    at == null || now.isBefore(at)
    ? 0
    : now.difference(at).inMilliseconds / 60000;

double sceneReportAge(SceneTrain train, Scene scene, DateTime now) =>
    train.ageMin +
    _elapsedMinutes(_anchor(train.snapshotAt, scene.savedAt), now);

/// A stopped report cannot establish passage while the device waits for a check.
Predict? currentPrediction(Predict? snapshot, DateTime now) {
  if (snapshot == null || snapshot.offline) return snapshot;
  final elapsed = _elapsedMinutes(
    _anchor(snapshot.generatedAt, snapshot.savedAt),
    now,
  );
  final stale = <String, List<Approach>>{};
  for (final train in snapshot.approaching) {
    if ((train.runInfo.atStation || train.runInfo.run == "at") &&
        (train.ageMin ?? 0) + elapsed >= 8) {
      stale.putIfAbsent(train.train, () => []).add(train);
    }
  }
  if (stale.isEmpty) return snapshot;
  final awaiting = {for (final row in snapshot.awaitingUpdate) row.number: row};
  for (final entry in stale.entries) {
    final row = entry.value.first;
    awaiting[entry.key] = AwaitingTrain(
      number: row.train,
      name: row.name,
      current: row.runInfo.current.isEmpty
          ? "the station"
          : row.runInfo.current,
      ageMin: (row.ageMin ?? 0) + elapsed,
      ids: {
        ...?awaiting[entry.key]?.ids,
        for (final approach in entry.value) ...approach.ids,
      }.toList(),
    );
  }
  return Predict(
    awaitingUpdate: awaiting.values.toList(),
    coverage: snapshot.coverage,
    gatePredictions: snapshot.gatePredictions
        ?.where((row) => !stale.containsKey(row.train))
        .toList(),
    error: snapshot.error,
    crossings: snapshot.crossings,
    stations: snapshot.stations,
    checked: snapshot.checked,
    running: snapshot.running,
    approaching: snapshot.approaching
        .where((row) => !stale.containsKey(row.train))
        .toList(),
    passed: snapshot.passed
        .where((row) => !stale.containsKey(row.train))
        .toList(),
    sightings: snapshot.sightings
        .where((row) => !stale.containsKey(row.number))
        .toList(),
    offline: snapshot.offline,
    savedAt: snapshot.savedAt,
    generatedAt: snapshot.generatedAt,
  );
}

Scene? currentScene(Scene? snapshot, DateTime now) {
  if (snapshot == null || snapshot.offline) return snapshot;
  final stale = snapshot.trains.where(
    (row) =>
        row.movement == "stopped" && sceneReportAge(row, snapshot, now) >= 8,
  );
  if (stale.isEmpty) return snapshot;
  final awaiting = {for (final row in snapshot.awaitingUpdate) row.number: row};
  for (final row in stale) {
    awaiting[row.number] = AwaitingTrain(
      number: row.number,
      name: row.name,
      current: row.current.isEmpty ? "the station" : row.current,
      ageMin: sceneReportAge(row, snapshot, now),
      ids: {
        ...?awaiting[row.number]?.ids,
        if (snapshot.crossing != null) snapshot.crossing!.id,
      }.toList(),
    );
  }
  final numbers = stale.map((row) => row.number).toSet();
  return Scene(
    available: snapshot.available,
    awaitingUpdate: awaiting.values.toList(),
    coverage: snapshot.coverage,
    error: snapshot.error,
    crossing: snapshot.crossing,
    rail: snapshot.rail,
    trains: snapshot.trains
        .where((row) => !numbers.contains(row.number))
        .toList(),
    passed: snapshot.passed
        .where((row) => !numbers.contains(row.number))
        .toList(),
    offline: snapshot.offline,
    savedAt: snapshot.savedAt,
  );
}

/// A newer gate check replaces only that gate's part of the nearby result.
Predict? withGateChecks(
  Predict? snapshot,
  List<Scene> checks,
  List<Gate> gates,
) {
  if (snapshot == null || snapshot.gatePredictions == null) return snapshot;
  var exact = [...snapshot.gatePredictions!];
  var approaching = [...snapshot.approaching];
  var awaiting = [...snapshot.awaitingUpdate];
  var passed = [...snapshot.passed];
  final predictionAt = snapshot.savedAt ?? snapshot.generatedAt;
  for (final check in checks) {
    final crossing = check.crossing;
    if (crossing == null ||
        !check.available ||
        check.offline ||
        check.error.isNotEmpty ||
        (check.savedAt?.millisecondsSinceEpoch ?? 0) <
            (predictionAt?.millisecondsSinceEpoch ?? 0)) {
      continue;
    }
    final gate = gates.where((row) => row.id == crossing.id).firstOrNull;
    exact = exact.where((row) => row.id != crossing.id).toList();
    exact.addAll(
      check.trains.map(
        (row) => GatePrediction(
          id: crossing.id,
          train: row.number,
          eta: row.etaMin,
          closesIn: row.closesInMin,
          status: row.status,
        ),
      ),
    );
    approaching = approaching.expand((row) {
      if (!row.ids.contains(crossing.id)) return [row];
      final ids = row.ids.where((id) => id != crossing.id).toList();
      if (ids.isEmpty) return <Approach>[];
      final remaining = exact.where(
        (mark) => mark.train == row.train && ids.contains(mark.id),
      );
      final next = remaining.isEmpty
          ? null
          : remaining.reduce((a, b) => a.eta < b.eta ? a : b);
      return [_remainingApproach(row, ids, next)];
    }).toList();
    for (final row in check.trains) {
      approaching.add(
        Approach(
          train: row.number,
          name: row.name,
          cluster: gate?.name ?? crossing.name,
          count: 1,
          eta: row.etaMin,
          status: row.status,
          fromYouKm: gate?.km ?? 0,
          lat: crossing.lat,
          lon: crossing.lon,
          ids: [crossing.id],
          runInfo: RunInfo(
            current: row.current,
            atStation: row.movement == "stopped",
            run: row.movement == "stopped" ? "at" : "",
          ),
          closesIn: row.closesInMin,
          ageMin: row.ageMin,
          basis: row.basis,
          bracket: row.bracket,
        ),
      );
    }
    awaiting = awaiting.expand((row) {
      if (!row.ids.contains(crossing.id)) return [row];
      final ids = row.ids.where((id) => id != crossing.id).toList();
      return ids.isEmpty
          ? <AwaitingTrain>[]
          : [
              AwaitingTrain(
                number: row.number,
                name: row.name,
                current: row.current,
                ageMin: row.ageMin,
                ids: ids,
              ),
            ];
    }).toList();
    awaiting.addAll(
      check.awaitingUpdate.map(
        (row) => AwaitingTrain(
          number: row.number,
          name: row.name,
          current: row.current,
          ageMin: row.ageMin,
          ids: [crossing.id],
        ),
      ),
    );
    passed = passed.expand((row) {
      if (!row.ids.contains(crossing.id)) return [row];
      final ids = row.ids.where((id) => id != crossing.id).toList();
      return ids.isEmpty
          ? <Passed>[]
          : [
              Passed(
                train: row.train,
                name: row.name,
                cluster: row.cluster,
                ago: row.ago,
                ids: ids,
              ),
            ];
    }).toList();
    passed.addAll(
      check.passed.map(
        (row) => Passed(
          train: row.number,
          name: row.name,
          cluster: gate?.name ?? crossing.name,
          ago: row.agoMin,
          ids: [crossing.id],
        ),
      ),
    );
  }
  final merged = <String, AwaitingTrain>{};
  for (final row in awaiting) {
    merged[row.number] = AwaitingTrain(
      number: row.number,
      name: row.name,
      current: row.current,
      ageMin: row.ageMin,
      ids: {...?merged[row.number]?.ids, ...row.ids}.toList(),
    );
  }
  return Predict(
    gatePredictions: exact,
    approaching: approaching,
    awaitingUpdate: merged.values.toList(),
    passed: passed,
    coverage: snapshot.coverage,
    error: snapshot.error,
    crossings: snapshot.crossings,
    stations: snapshot.stations,
    checked: snapshot.checked,
    running: snapshot.running,
    sightings: snapshot.sightings,
    offline: snapshot.offline,
    savedAt: snapshot.savedAt,
    generatedAt: snapshot.generatedAt,
  );
}

Approach _remainingApproach(
  Approach row,
  List<String> ids,
  GatePrediction? next,
) => Approach(
  train: row.train,
  name: row.name,
  cluster: row.cluster,
  count: ids.length,
  eta: next?.eta ?? row.eta,
  status: next?.status ?? row.status,
  fromYouKm: row.fromYouKm,
  lat: row.lat,
  lon: row.lon,
  ids: ids,
  runInfo: row.runInfo,
  bracket: row.bracket,
  closesIn: next?.closesIn ?? row.closesIn,
  ageMin: row.ageMin,
  basis: row.basis,
);
