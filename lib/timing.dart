import "models.dart";
import "geo.dart";

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

Map<String, Spot> sceneTrainPositions(Scene? scene, DateTime now) {
  if (scene == null || scene.offline || scene.rail.length < 2) return {};
  return {
    for (final train in scene.trains)
      if (train.observed != false &&
          train.positionOnSegment &&
          sceneReportAge(train, scene, now) < 8)
        train.identity: pointAlongKm(scene.rail, train.alongKm),
  };
}

/// An expired observation cannot establish passage while the device waits for a check.
Predict? currentPrediction(Predict? snapshot, DateTime now) {
  if (snapshot == null || snapshot.offline) return snapshot;
  final elapsed = _elapsedMinutes(
    _anchor(snapshot.generatedAt, snapshot.savedAt),
    now,
  );
  final stale = <String, List<Approach>>{};
  for (final train in snapshot.approaching) {
    final age = train.ageMin;
    if (train.observed != false && age != null && age + elapsed >= 8) {
      stale.putIfAbsent(train.identity, () => []).add(train);
    }
  }
  if (stale.isEmpty) return snapshot;
  final awaiting = {
    for (final row in snapshot.awaitingUpdate) row.identity: row,
  };
  for (final entry in stale.entries) {
    final row = entry.value.first;
    awaiting[entry.key] = AwaitingTrain(
      number: row.train,
      runId: row.runId,
      startDate: row.startDate,
      name: row.name,
      current: row.runInfo.current,
      reason: row.runInfo.atStation || row.runInfo.run == "at"
          ? "stopped_report"
          : "stale_report",
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
    serviceUpdates: snapshot.serviceUpdates,
    gatePredictions: snapshot.gatePredictions
        ?.where((row) => !stale.containsKey(row.identity))
        .toList(),
    error: snapshot.error,
    mapWarning: snapshot.mapWarning,
    mapAgeSeconds: snapshot.mapAgeSeconds,
    crossings: snapshot.crossings,
    stations: snapshot.stations,
    checked: snapshot.checked,
    running: snapshot.running,
    approaching: snapshot.approaching
        .where((row) => !stale.containsKey(row.identity))
        .toList(),
    passed: snapshot.passed
        .where((row) => !stale.containsKey(row.identity))
        .toList(),
    sightings: snapshot.sightings
        .where((row) => !stale.containsKey(row.identity))
        .toList(),
    offline: snapshot.offline,
    savedAt: snapshot.savedAt,
    generatedAt: snapshot.generatedAt,
  );
}

Scene? currentScene(Scene? snapshot, DateTime now) {
  if (snapshot == null || snapshot.offline) return snapshot;
  final stale = snapshot.trains.where(
    (row) => row.observed != false && sceneReportAge(row, snapshot, now) >= 8,
  );
  if (stale.isEmpty) return snapshot;
  final awaiting = {
    for (final row in snapshot.awaitingUpdate) row.identity: row,
  };
  for (final row in stale) {
    awaiting[row.identity] = AwaitingTrain(
      number: row.number,
      runId: row.runId,
      startDate: row.startDate,
      name: row.name,
      current: row.current,
      reason: row.movement == "stopped" ? "stopped_report" : "stale_report",
      ageMin: sceneReportAge(row, snapshot, now),
      ids: {
        ...?awaiting[row.identity]?.ids,
        if (snapshot.crossing != null) snapshot.crossing!.id,
      }.toList(),
    );
  }
  final numbers = stale.map((row) => row.identity).toSet();
  return Scene(
    available: snapshot.available,
    awaitingUpdate: awaiting.values.toList(),
    coverage: snapshot.coverage,
    serviceUpdates: snapshot.serviceUpdates,
    error: snapshot.error,
    mapWarning: snapshot.mapWarning,
    mapAgeSeconds: snapshot.mapAgeSeconds,
    crossing: snapshot.crossing,
    rail: snapshot.rail,
    trains: snapshot.trains
        .where((row) => !numbers.contains(row.identity))
        .toList(),
    passed: snapshot.passed
        .where((row) => !numbers.contains(row.identity))
        .toList(),
    offline: snapshot.offline,
    savedAt: snapshot.savedAt,
    legacyAliasResolved: snapshot.legacyAliasResolved,
  );
}

/// A newer gate check replaces only that gate's part of the nearby result.
Predict? withGateChecks(
  Predict? snapshot,
  List<Scene> checks,
  List<Gate> gates,
) {
  if (snapshot == null || checks.isEmpty) return snapshot;
  var exact = [
    ...(snapshot.gatePredictions ??
        [
          for (final row in snapshot.approaching)
            if (row.ids.length == 1)
              GatePrediction(
                id: row.ids.single,
                train: row.train,
                runId: row.runId,
                startDate: row.startDate,
                eta: row.eta,
                closesIn: row.closesIn,
                status: row.status,
              ),
        ]),
  ];
  var approaching = [...snapshot.approaching];
  var awaiting = [...snapshot.awaitingUpdate];
  var passed = [...snapshot.passed];
  final updates = {
    for (final row in snapshot.serviceUpdates) row.identity: row,
  };
  final predictionAt = snapshot.savedAt ?? snapshot.generatedAt;
  var coverage = snapshot.coverage;
  final ordered = [...checks]
    ..sort(
      (a, b) => (a.savedAt?.millisecondsSinceEpoch ?? 0).compareTo(
        b.savedAt?.millisecondsSinceEpoch ?? 0,
      ),
    );
  for (final check in ordered) {
    final crossing = check.crossing;
    if (crossing == null ||
        !check.available ||
        check.offline ||
        check.error.isNotEmpty ||
        (check.savedAt?.millisecondsSinceEpoch ?? 0) <
            (predictionAt?.millisecondsSinceEpoch ?? 0)) {
      continue;
    }
    for (final row in check.trains) {
      if (row.observed != false) updates.remove(row.identity);
    }
    for (final row in check.serviceUpdates) {
      updates[row.identity] = row;
    }
    if (check.incomplete && coverage?.incomplete != true) {
      coverage = check.coverage?.incomplete == true
          ? check.coverage
          : const TrainCoverage(status: "partial");
    }
    final explicit = {
      ...check.trains.map((row) => row.identity),
      ...check.awaitingUpdate.map((row) => row.identity),
      ...check.passed.map((row) => row.identity),
      ...check.serviceUpdates.map((row) => row.identity),
    };
    bool replaces(String id) => !check.incomplete || explicit.contains(id);
    final gate = gates.where((row) => row.id == crossing.id).firstOrNull;
    exact = [
      for (final row in exact)
        if (row.id != crossing.id)
          row
        else if (!replaces(row.identity))
          row.asEarlierEstimate(),
    ];
    exact.addAll(
      check.trains.map(
        (row) => GatePrediction(
          id: crossing.id,
          train: row.number,
          runId: row.runId,
          startDate: row.startDate,
          eta: row.etaMin,
          closesIn: row.closesInMin,
          status: row.status,
        ),
      ),
    );
    approaching = approaching.expand((row) {
      if (!row.ids.contains(crossing.id) || !replaces(row.identity))
        return [row];
      final ids = row.ids.where((id) => id != crossing.id).toList();
      if (ids.isEmpty) return <Approach>[];
      final remaining = exact.where(
        (mark) => mark.identity == row.identity && ids.contains(mark.id),
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
          runId: row.runId,
          startDate: row.startDate,
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
          observed: row.observed,
        ),
      );
    }
    awaiting = awaiting.expand((row) {
      if (!row.ids.contains(crossing.id) || !replaces(row.identity))
        return [row];
      final ids = row.ids.where((id) => id != crossing.id).toList();
      return ids.isEmpty
          ? <AwaitingTrain>[]
          : [
              AwaitingTrain(
                number: row.number,
                runId: row.runId,
                startDate: row.startDate,
                name: row.name,
                current: row.current,
                ageMin: row.ageMin,
                reason: row.reason,
                ids: ids,
              ),
            ];
    }).toList();
    awaiting.addAll(
      check.awaitingUpdate.map(
        (row) => AwaitingTrain(
          number: row.number,
          runId: row.runId,
          startDate: row.startDate,
          name: row.name,
          current: row.current,
          ageMin: row.ageMin,
          reason: row.reason,
          ids: [crossing.id],
        ),
      ),
    );
    passed = passed.expand((row) {
      if (!row.ids.contains(crossing.id) || !replaces(row.identity))
        return [row];
      final ids = row.ids.where((id) => id != crossing.id).toList();
      return ids.isEmpty
          ? <Passed>[]
          : [
              Passed(
                train: row.train,
                runId: row.runId,
                startDate: row.startDate,
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
          runId: row.runId,
          startDate: row.startDate,
          name: row.name,
          cluster: gate?.name ?? crossing.name,
          ago: row.agoMin,
          ids: [crossing.id],
        ),
      ),
    );
  }
  exact = exact.where((row) => !updates.containsKey(row.identity)).toList();
  approaching = approaching
      .where((row) => !updates.containsKey(row.identity))
      .toList();
  awaiting = awaiting
      .where((row) => !updates.containsKey(row.identity))
      .toList();
  passed = passed.where((row) => !updates.containsKey(row.identity)).toList();
  final merged = <String, AwaitingTrain>{};
  for (final row in awaiting) {
    merged[row.identity] = AwaitingTrain(
      number: row.number,
      runId: row.runId,
      startDate: row.startDate,
      name: row.name,
      current: row.current,
      ageMin: row.ageMin,
      reason: row.reason,
      ids: {...?merged[row.identity]?.ids, ...row.ids}.toList(),
    );
  }
  return Predict(
    gatePredictions: exact,
    approaching: approaching,
    awaitingUpdate: merged.values.toList(),
    passed: passed,
    coverage: coverage,
    serviceUpdates: updates.values.toList(),
    error: snapshot.error,
    mapWarning: snapshot.mapWarning,
    mapAgeSeconds: snapshot.mapAgeSeconds,
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
  runId: row.runId,
  startDate: row.startDate,
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
  observed: row.observed,
);
