import "models.dart";

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
String gateLabel(double eta, [double? closesIn]) {
  final downIn = closesIn ?? eta;
  if (downIn <= 0) {
    return eta <= 1
        ? "closed · train passing"
        : "closed · train in ${eta.round()} min";
  }
  if (downIn < 1) return "closing now";
  return "closes in ${_span(downIn)}";
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

List<Gate> markGates(List<Gate> gates, Predict? predict) {
  final marks = <String, GatePrediction>{};
  final rows =
      predict?.gatePredictions ??
      [
        for (final row in predict?.approaching ?? const <Approach>[])
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
    if (previous == null || row.eta < previous.eta) marks[row.id] = row;
  }
  return [
    for (final gate in gates)
      Gate(
        id: gate.id,
        name: gate.name,
        lat: gate.lat,
        lon: gate.lon,
        km: gate.km,
        source: gate.source,
        status: marks[gate.id]?.status,
        eta: marks[gate.id]?.eta,
        closesIn: marks[gate.id]?.closesIn,
      ),
  ];
}

List<Gate> shownGates(List<Gate> gates) {
  final ranked = [...gates]
    ..sort((a, b) {
      final hot = (a.eta == null ? 1 : 0).compareTo(b.eta == null ? 1 : 0);
      if (hot != 0) return hot;
      if (a.eta != null && b.eta != null && a.eta != b.eta) {
        return a.eta!.compareTo(b.eta!);
      }
      return a.km.compareTo(b.km);
    });
  final hot = ranked.where((gate) => gate.eta != null);
  final rest = ranked.where((gate) => gate.eta == null).take(12);
  return [...hot, ...rest];
}

Map<String, List<Approach>> groupApproaches(List<Approach> rows) {
  final grouped = <String, List<Approach>>{};
  for (final row in rows) {
    grouped.putIfAbsent(row.train, () => []).add(row);
  }
  for (final list in grouped.values) {
    list.sort((a, b) => a.eta.compareTo(b.eta));
  }
  return grouped;
}

List<Sighting> lineSightings(Predict predict) {
  final shown = {
    ...predict.approaching.map((row) => row.train),
    ...predict.passed.map((row) => row.train),
  };
  return predict.sightings
      .where(
        (row) =>
            row.age < 45 && !row.passedLocal && !shown.contains(row.number),
      )
      .take(6)
      .toList();
}
