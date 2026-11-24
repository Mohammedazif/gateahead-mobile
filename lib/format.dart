import "models.dart";
import "timing.dart";

String checkedAgo(DateTime at, DateTime now) {
  final minutes = now.difference(at).inMinutes;
  if (minutes < 1) return "Checked just now";
  if (minutes < 60) return "Checked $minutes min ago";
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (mins == 0) return "Checked $hours hr ago";
  return "Checked $hours hr $mins min ago";
}

String friendlyError(String? message) {
  if (message == null || message.isEmpty) {
    return "Something went wrong. Try again in a moment.";
  }
  if (RegExp(
    r"429|502|504|timeout|timed out|busy|map_busy",
    caseSensitive: false,
  ).hasMatch(message)) {
    return "The crossing list is busy. Wait a minute and try again.";
  }
  if (RegExp(
    r"406|overpass|map_unavailable|could not reach|invalid data",
    caseSensitive: false,
  ).hasMatch(message)) {
    return "The crossing list did not load. Try again in a minute.";
  }
  if (message == "crossing_not_found") {
    return "That crossing is no longer on the map.";
  }
  return message;
}

String mapWarningLabel(double? ageSeconds) {
  if (ageSeconds == null) {
    return "The map could not be fully refreshed. Some crossings may be missing.";
  }
  final minutes = (ageSeconds / 60).floor();
  final age = minutes < 1 ? "less than 1 min" : _span(minutes.toDouble());
  return "Showing map data from $age ago. Some crossings may be missing.";
}

String formatSpot(double lat, double lon) {
  final ns = lat >= 0 ? "N" : "S";
  final ew = lon >= 0 ? "E" : "W";
  return "${lat.abs().toStringAsFixed(4)}° $ns, ${lon.abs().toStringAsFixed(4)}° $ew";
}

String cleanPlace(String value) {
  return value
      .replaceAll("~", " ")
      .split(RegExp(r"\s+"))
      .where((word) => word.isNotEmpty)
      .map((word) {
        final key = word.toUpperCase().replaceAll(".", "");
        if (key == "JN") return "Jn";
        if (key == "CNTL") return "Central";
        if (word == word.toUpperCase()) {
          return word[0] + word.substring(1).toLowerCase();
        }
        return word;
      })
      .join(" ");
}

String _km(double km) => km == km.roundToDouble() ? "${km.round()}" : "$km";

String delayLabel(int minutes) {
  if (minutes > 0) return "$minutes min late";
  if (minutes < 0) return "${minutes.abs()} min early";
  return "On time";
}

String delayClass(int minutes) {
  if (minutes > 0) return "late";
  if (minutes < 0) return "early";
  return "ontime";
}

/// When the barrier comes down, or that it is down. Same wording as the website and the bot.
///
/// [eta] is minutes until the train reaches the crossing; [closesIn] is minutes until the barrier
/// comes down (zero or less: down now). An older API without [closesIn] counts down to the train.
String gateLabel(double eta, [double? closesIn, String? status]) {
  final downIn = closesIn ?? eta;
  if (status == "approaching" && downIn <= 0) return "train timing uncertain";
  if (downIn <= 0) {
    return eta <= 0
        ? "closed · train passing"
        : eta < 1
        ? "closed · train due within 1 min"
        : "closed · train in ${eta.round()} min";
  }
  if (downIn < 1) return "closing now";
  return "closes in ${_span(downIn)}";
}

String sceneTimingLabel(
  SceneTrain train,
  Scene scene,
  DateTime now, {
  required bool historical,
}) {
  if (historical) {
    return train.etaMin <= 0
        ? "Estimated passing window at check"
        : "Train was due in ${train.etaMin.ceil()} min at check";
  }
  if (train.movement == "stopped") {
    return "Departure timing uncertain";
  }
  final elapsed = sceneEstimateAge(train, scene, now);
  final eta = train.etaMin - elapsed;
  final closes = train.closesInMin == null
      ? null
      : train.closesInMin! - elapsed;
  if (train.observed == false) {
    return eta > 0
        ? "Scheduled train in ${eta.ceil()} min"
        : "Scheduled arrival time has elapsed";
  }
  if (eta <= 0) {
    return eta < -2 || train.status == "approaching" || train.status == "later"
        ? "Estimated arrival time has elapsed"
        : "Estimated passing window";
  }
  if (closes == null) return "Train estimated in ${eta.ceil()} min";
  if (closes <= 0) {
    return train.status == "closed" || train.status == "closing_soon"
        ? "Estimated closure window · train due in ${eta.ceil()} min"
        : "Barrier timing uncertain · train estimated in ${eta.ceil()} min";
  }
  return gateLabel(eta, closes, train.status);
}

String passedLabel(double ago) {
  if (ago < 1) return "passed just now";
  return "passed ${ago.round()} min ago";
}

String _span(double minutes) {
  if (minutes >= 60) {
    var hours = minutes ~/ 60;
    var mins = (minutes - hours * 60).round();
    if (mins == 60) {
      hours += 1;
      mins = 0;
    }
    if (mins == 0) return "$hours hr";
    return "$hours hr $mins min";
  }
  return "${minutes.round()} min";
}

String labelStatus(String status) {
  switch (status) {
    case "closed":
      return "Closed";
    case "closing_soon":
      return "Closing";
    case "approaching":
      return "Approaching";
    case "later":
      return "Later";
    case "passed":
      return "Passed";
    default:
      return status;
  }
}

class RunCopy {
  const RunCopy({
    this.route,
    this.place,
    this.scheduled,
    this.delay,
    this.next,
  });

  final String? route;
  final String? place;
  final String? scheduled;
  final String? delay;
  final String? next;
}

RunCopy runCopy(RunInfo row, {bool showDelay = false}) {
  final where = cleanPlace(row.current);
  var place = "";
  if (row.run == "departed" && row.departedAt.isNotEmpty && where.isNotEmpty) {
    place = "Departed $where at ${row.departedAt}";
  } else if ((row.run == "at" || row.atStation) && where.isNotEmpty) {
    place = "At $where";
  } else if (where.isNotEmpty) {
    place = "Last reported at $where";
  }
  if (place.isNotEmpty && row.platform.isNotEmpty) {
    place = "$place, platform ${row.platform}";
  }
  final nextParts = <String>[
    if (row.nextStop.isNotEmpty) "Next ${cleanPlace(row.nextStop)}",
    if (row.nextIn.isNotEmpty) row.nextIn,
    if (row.leftKm != null && row.leftKm != 0) "${_km(row.leftKm!)} km left",
  ];
  return RunCopy(
    route: row.origin.isNotEmpty && row.dest.isNotEmpty
        ? "${cleanPlace(row.origin)} to ${cleanPlace(row.dest)}"
        : null,
    place: place.isEmpty ? null : place,
    scheduled: row.scheduledAt.isEmpty ? null : "Scheduled ${row.scheduledAt}",
    delay: showDelay && row.delay != 0 ? delayLabel(row.delay) : null,
    next: nextParts.isEmpty ? null : nextParts.join(" · "),
  );
}

List<Gate> markGates(
  List<Gate> gates,
  Predict? predict, [
  List<Scene> checked = const [],
]) {
  var evidence = predict;
  if (checked.isNotEmpty) {
    evidence = withGateChecks(
      predict ?? const Predict(gatePredictions: []),
      checked,
      gates,
    );
  }
  final marks = <String, GatePrediction>{};
  final uncertain = {
    for (final train in evidence?.awaitingUpdate ?? const <AwaitingTrain>[])
      ...train.ids,
  };
  final rows =
      evidence?.gatePredictions ??
      [
        for (final row in evidence?.approaching ?? const <Approach>[])
          if (row.ids.length == 1)
            GatePrediction(
              id: row.ids.single,
              eta: row.eta,
              status: row.status,
              closesIn: row.closesIn,
            ),
      ];
  for (final row in rows) {
    final previous = marks[row.id];
    if (previous == null ||
        row.eta < previous.eta ||
        (row.eta == previous.eta &&
            previous.earlierEstimate &&
            !row.earlierEstimate)) {
      marks[row.id] = row;
    }
  }
  bool showEstimate(String id) =>
      !uncertain.contains(id) ||
      const ["closed", "closing_soon"].contains(marks[id]?.status);
  return [
    for (final gate in gates)
      Gate(
        id: gate.id,
        name: gate.name,
        lat: gate.lat,
        lon: gate.lon,
        km: gate.km,
        source: gate.source,
        groupId: gate.groupId,
        groupName: gate.groupName,
        groupSize: gate.groupSize,
        road: gate.road,
        area: gate.area,
        status: showEstimate(gate.id) ? marks[gate.id]?.status : "uncertain",
        eta: showEstimate(gate.id) ? marks[gate.id]?.eta : null,
        closesIn: showEstimate(gate.id) ? marks[gate.id]?.closesIn : null,
        hasUncertainTrain: uncertain.contains(gate.id),
        earlierEstimate: marks[gate.id]?.earlierEstimate == true,
      ),
  ];
}

List<Gate> shownGates(List<Gate> gates) {
  bool active(Gate gate) => gate.eta != null || gate.status == "uncertain";
  final ranked = [...gates]
    ..sort((a, b) {
      final hot = (active(a) ? 0 : 1).compareTo(active(b) ? 0 : 1);
      if (hot != 0) return hot;
      if (a.eta != null && b.eta != null && a.eta != b.eta) {
        return a.eta!.compareTo(b.eta!);
      }
      return a.km.compareTo(b.km);
    });
  final hot = ranked.where(active);
  final rest = ranked.where((gate) => !active(gate)).take(12);
  return [...hot, ...rest];
}

/// A presentation group. Every member retains its own scene, ID and estimate.
class PhysicalCrossing {
  PhysicalCrossing(this.members);

  final List<Gate> members;
  Gate get first => members.first;
  String get key => first.groupId.isEmpty ? "gate:${first.id}" : first.groupId;
  String get name => first.groupName.isNotEmpty
      ? first.groupName
      : first.name.isNotEmpty
      ? first.name
      : "Level crossing";
  double get km =>
      members.map((gate) => gate.km).reduce((a, b) => a < b ? a : b);
  bool get active =>
      members.any((gate) => gate.eta != null || gate.status == "uncertain");
  List<Gate> get timed =>
      members
          .where((gate) => gate.eta != null && gate.status != "uncertain")
          .toList()
        ..sort((a, b) => a.eta!.compareTo(b.eta!));
  int get uncertainCount => members
      .where((gate) => gate.hasUncertainTrain || gate.status == "uncertain")
      .length;
}

List<PhysicalCrossing> physicalCrossings(List<Gate> gates) {
  final groups = <String, List<Gate>>{};
  for (final gate in gates) {
    final key = gate.groupId.isEmpty
        ? "gate:${gate.id}"
        : "group:${gate.groupId}";
    groups.putIfAbsent(key, () => []).add(gate);
  }
  return [for (final members in groups.values) PhysicalCrossing(members)];
}

String? trackCrossingLabel(Gate? gate, List<Gate> gates) {
  if (gate == null || gate.groupId.isEmpty) return null;
  final ids =
      gates
          .where((item) => item.groupId == gate.groupId)
          .map((item) => item.id)
          .toList()
        ..sort();
  final size = ids.length > gate.groupSize ? ids.length : gate.groupSize;
  if (size < 2) return null;
  final index = ids.indexOf(gate.id);
  return ids.length == size && index >= 0
      ? "Track crossing ${index + 1} of $size"
      : "Part of $size track crossings";
}

List<PhysicalCrossing> shownCrossings(
  List<Gate> gates, {
  bool showAll = false,
}) {
  final ranked = physicalCrossings(gates)
    ..sort((a, b) {
      final hot = (a.active ? 0 : 1).compareTo(b.active ? 0 : 1);
      if (hot != 0) return hot;
      if (a.timed.isNotEmpty && b.timed.isNotEmpty) {
        final eta = a.timed.first.eta!.compareTo(b.timed.first.eta!);
        if (eta != 0) return eta;
      }
      return a.km.compareTo(b.km);
    });
  if (showAll) return ranked;
  return [
    ...ranked.where((crossing) => crossing.active),
    ...ranked.where((crossing) => !crossing.active).take(12),
  ];
}

/// Only rows entirely mapped to the same explicit crossing group can combine.
/// A run ID (or its date-aware fallback) also forms part of the key.
class CrossingApproaches {
  CrossingApproaches(this.rows, {this.name = "", this.groupId = ""});
  final List<Approach> rows;
  final String name, groupId;
  Set<String> get ids => {for (final row in rows) ...row.ids};
  bool get grouped => groupId.isNotEmpty && ids.length > 1;
}

List<CrossingApproaches> crossingApproaches(
  List<Approach> rows,
  List<Gate> gates,
) {
  final byId = {for (final gate in gates) gate.id: gate};
  final groups = <String, CrossingApproaches>{};
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final members = [for (final id in row.ids) byId[id]];
    final groupId =
        members.isNotEmpty &&
            members.every((gate) => gate != null && gate.groupId.isNotEmpty) &&
            members.map((gate) => gate!.groupId).toSet().length == 1
        ? members.first!.groupId
        : "";
    final key = groupId.isEmpty ? "row:$i" : "${row.identity}:$groupId";
    final first = members.firstOrNull;
    groups
        .putIfAbsent(
          key,
          () => CrossingApproaches(
            [],
            groupId: groupId,
            name: first?.groupName.isNotEmpty == true
                ? first!.groupName
                : row.cluster.isEmpty
                ? "Level crossing"
                : row.cluster,
          ),
        )
        .rows
        .add(row);
  }
  return [
    for (final group in groups.values)
      if (group.ids.length > 1)
        group
      else
        for (final row in group.rows)
          CrossingApproaches([row], name: group.name, groupId: group.groupId),
  ];
}

Map<String, List<Approach>> groupApproaches(List<Approach> rows) {
  final grouped = <String, List<Approach>>{};
  for (final row in rows) {
    grouped.putIfAbsent(row.identity, () => []).add(row);
  }
  for (final list in grouped.values) {
    list.sort((a, b) => a.eta.compareTo(b.eta));
  }
  return grouped;
}

/// Cluster estimates cannot supply separate timings for all their track nodes.
/// Prefer the exact rows for this journey; older replies still use their cluster row.
List<Approach> trainCrossingRows(Predict predict, List<Gate> gates) {
  final byId = {for (final gate in gates) gate.id: gate};
  final result = <Approach>[];
  for (final entry in groupApproaches(predict.approaching).entries) {
    final exact = <String, GatePrediction>{};
    for (final row in predict.gatePredictions ?? const <GatePrediction>[]) {
      if (row.identity != entry.key) continue;
      final old = exact[row.id];
      if (old == null || row.eta < old.eta) exact[row.id] = row;
    }
    if (exact.isEmpty) {
      result.addAll(entry.value);
      continue;
    }
    for (final row in exact.values) {
      final original = entry.value.firstWhere(
        (approach) => approach.ids.contains(row.id),
        orElse: () => entry.value.first,
      );
      final gate = byId[row.id];
      result.add(
        Approach(
          runId: original.runId,
          startDate: original.startDate,
          train: original.train,
          name: original.name,
          cluster: gate?.name ?? original.cluster,
          count: 1,
          eta: row.eta,
          status: row.status,
          fromYouKm: gate?.km ?? original.fromYouKm,
          lat: gate?.lat ?? original.lat,
          lon: gate?.lon ?? original.lon,
          ids: [row.id],
          runInfo: original.runInfo,
          bracket: original.bracket,
          closesIn: row.closesIn,
          ageMin: original.ageMin,
          basis: original.basis,
        ),
      );
    }
  }
  return result;
}

List<Sighting> lineSightings(Predict predict) {
  final shown = {
    ...predict.approaching.map((row) => row.identity),
    ...predict.passed.map((row) => row.identity),
    ...predict.awaitingUpdate.map((row) => row.identity),
  };
  return predict.sightings
      .where(
        (row) =>
            row.age < 45 && !row.passedLocal && !shown.contains(row.identity),
      )
      .take(6)
      .toList();
}
