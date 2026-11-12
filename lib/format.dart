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
  if (RegExp(r"429|502|504|timeout|timed out|busy|map_busy", caseSensitive: false).hasMatch(message)) {
    return "The crossing list is busy. Wait a minute and try again.";
  }
  if (RegExp(r"406|overpass|map_unavailable|could not reach|invalid data", caseSensitive: false).hasMatch(message)) {
    return "The crossing list did not load. Try again in a minute.";
  }
  if (message == "crossing_not_found") return "That crossing is no longer on the map.";
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

String etaLabel(double minutes) {
  if (minutes <= 1) return "closing now";
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final mins = (minutes % 60).round();
    if (mins == 0) return "closes in $hours hr";
    return "closes in $hours hr $mins min";
  }
  return "closes in ${minutes.round()} min";
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
    default:
      return status;
  }
}

class RunCopy {
  const RunCopy({this.route, this.place, this.scheduled, this.delay, this.next});

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
  final marks = <String, ({String status, double eta, String label})>{};
  for (final row in predict?.approaching ?? const <Approach>[]) {
    for (final id in row.ids) {
      final prev = marks[id];
      if (prev == null || row.eta < prev.eta) {
        marks[id] = (status: row.status, eta: row.eta, label: row.cluster);
      }
    }
  }
  if (marks.isEmpty) return gates;
  return [
    for (final gate in gates)
      if (marks[gate.id] case final mark?)
        gate.copyWith(
          name: mark.label.isEmpty ? gate.name : mark.label,
          status: mark.status,
          eta: mark.eta,
        )
      else
        gate,
  ];
}

List<Gate> shownGates(List<Gate> gates) {
  final ranked = [...gates]..sort((a, b) {
    final hot = (a.eta == null ? 1 : 0).compareTo(b.eta == null ? 1 : 0);
    if (hot != 0) return hot;
    if (a.eta != null && b.eta != null && a.eta != b.eta) return a.eta!.compareTo(b.eta!);
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
  final shown = predict.approaching.map((row) => row.train).toSet();
  return predict.sightings
      .where((row) => row.age < 45 && !row.passedLocal && !shown.contains(row.number))
      .take(6)
      .toList();
}
