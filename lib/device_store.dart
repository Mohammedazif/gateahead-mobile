import "dart:convert";
import "dart:math";

import "package:shared_preferences/shared_preferences.dart";

import "models.dart";

class SavedGate {
  const SavedGate(this.gate, this.label, this.place);
  final Gate gate;
  final String label;
  final Spot place;
  Map<String, Object?> toJson() => {
    "gate": {
      "id": gate.id,
      "name": gate.name,
      "lat": gate.lat,
      "lon": gate.lon,
      "km": gate.km,
      "source": gate.source,
    },
    "label": label,
    "lat": place.lat,
    "lon": place.lon,
  };
}

class RefreshSettings {
  const RefreshSettings({
    this.enabled = false,
    this.commute = false,
    this.start = "08:00",
    this.end = "10:00",
    this.weekdays = true,
  });
  final bool enabled, commute, weekdays;
  final String start, end;
  RefreshSettings copyWith({
    bool? enabled,
    bool? commute,
    String? start,
    String? end,
    bool? weekdays,
  }) => RefreshSettings(
    enabled: enabled ?? this.enabled,
    commute: commute ?? this.commute,
    start: start ?? this.start,
    end: end ?? this.end,
    weekdays: weekdays ?? this.weekdays,
  );
  Map<String, Object> toJson() => {
    "enabled": enabled,
    "commute": commute,
    "start": start,
    "end": end,
    "weekdays": weekdays,
  };
  bool allows(DateTime now) {
    if (!commute) return true;
    int clock(String value) {
      final bits = value.split(":");
      if (bits.length != 2) return -1;
      final h = int.tryParse(bits[0]), m = int.tryParse(bits[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return -1;
      }
      return h * 60 + m;
    }

    final from = clock(start), until = clock(end);
    if (from < 0 || until < 0 || from == until) return false;
    final minute = now.hour * 60 + now.minute;
    final overnight = from > until;
    final day = overnight && minute < until
        ? now.subtract(const Duration(days: 1)).weekday
        : now.weekday;
    if (weekdays && day > 5) return false;
    return overnight
        ? minute >= from || minute < until
        : minute >= from && minute < until;
  }
}

class CachedJson {
  const CachedJson(this.at, this.data);
  final DateTime at;
  final Map<String, dynamic> data;
  Map<String, dynamic> restored() => {
    ...data,
    "_offline": true,
    "_saved_at": at.millisecondsSinceEpoch,
  };
}

class DeviceStore {
  DeviceStore(this.preferences, {this.namespace = ""});
  final SharedPreferences preferences;
  final String namespace;

  dynamic read(String key) {
    try {
      return jsonDecode(
        preferences.getString("gateahead:$namespace:$key") ?? "null",
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> write(String key, Object? value) async {
    try {
      return await preferences.setString(
        "gateahead:$namespace:$key",
        jsonEncode(value),
      );
    } catch (_) {
      return false;
    }
  }

  List<SavedGate> favorites() {
    final data = read("favorites");
    if (data is! List) return [];
    final result = <SavedGate>[];
    for (final row in data.take(50)) {
      if (row is! Map) continue;
      final gate = Gate.tryParse(row["gate"]);
      final lat = row["lat"], lon = row["lon"], label = row["label"];
      if (gate == null ||
          !validCoordinates(gate.lat, gate.lon) ||
          !validCoordinates(lat, lon) ||
          label is! String) {
        continue;
      }
      result.add(
        SavedGate(
          gate,
          label,
          Spot((lat as num).toDouble(), (lon as num).toDouble()),
        ),
      );
    }
    return result;
  }

  RefreshSettings settings() {
    final row = read("refresh");
    if (row is! Map) return const RefreshSettings();
    return RefreshSettings(
      enabled: row["enabled"] == true,
      commute: row["commute"] == true,
      start: _validClock(row["start"]) ? row["start"] : "08:00",
      end: _validClock(row["end"]) ? row["end"] : "10:00",
      weekdays: row["weekdays"] != false,
    );
  }

  CachedJson? response(String key) {
    return _responses()[key];
  }

  Map<String, CachedJson> _responses() {
    final raw = read("responses");
    if (raw is! Map) return {};
    final result = <String, CachedJson>{};
    for (final entry in raw.entries) {
      final row = entry.value;
      if (entry.key is! String || row is! Map || row["data"] is! Map) continue;
      final at = storedDateTime(row["at"]);
      if (at == null) continue;
      final data = Map<String, dynamic>.from(row["data"]);
      final path = Uri.tryParse(entry.key)?.path ?? "";
      if (!validResponseBody(path, data) ||
          (data["error"] != null && data["error"] != "")) {
        continue;
      }
      result[entry.key] = CachedJson(at, data);
    }
    return result;
  }

  Future<DateTime> saveResponse(String key, Map<String, dynamic> data) async {
    final at = DateTime.now();
    final all = _responses();
    all[key] = CachedJson(at, data);
    final keys = all.keys.toList()
      ..sort((a, b) => all[b]!.at.compareTo(all[a]!.at));
    await write("responses", {
      for (final k in keys.take(24))
        k: {"at": all[k]!.at.millisecondsSinceEpoch, "data": all[k]!.data},
    });
    return at;
  }

  Future<String> installationId() async {
    final saved = read("installation");
    if (saved is String && saved.length >= 16) return saved;
    final random = Random.secure();
    final id = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, "0"),
    ).join();
    await write("installation", id);
    return id;
  }
}

bool validCoordinates(Object? lat, Object? lon) =>
    lat is num &&
    lon is num &&
    lat.isFinite &&
    lon.isFinite &&
    lat.abs() <= 90 &&
    lon.abs() <= 180;

DateTime? storedDateTime(Object? value) {
  if (value is! int) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(value);
  } on RangeError {
    return null;
  }
}

bool _validClock(Object? value) =>
    value is String && RegExp(r"^([01]\d|2[0-3]):[0-5]\d$").hasMatch(value);

/// Reject unusable cached containers before parsers or UI consumers see them.
bool validResponseBody(String path, Map<String, dynamic> data) {
  if (data["error"] is String && (data["error"] as String).isNotEmpty) {
    return true;
  }
  if (path == "/gates" && data["gates"] is! List) return false;
  if (path == "/predict" && data["approaching"] is! List) return false;
  if (path == "/scene" &&
      (data["available"] is! bool || data["trains"] is! List)) {
    return false;
  }
  final fields = switch (path) {
    "/predict" => [
      "stations",
      "approaching",
      "passed",
      "sightings",
      "gate_predictions",
      "awaiting_update",
      "service_updates",
    ],
    "/scene" => [
      "rail",
      "trains",
      "passed",
      "awaiting_update",
      "service_updates",
    ],
    "/gates" => ["gates"],
    _ => <String>[],
  };
  for (final field in fields) {
    final rows = data[field];
    if (rows == null) continue;
    if (rows is! List) return false;
    for (final row in rows) {
      if (row is Map && row["ids"] != null && row["ids"] is! List) return false;
      if (row is Map) {
        for (final key in ["run_id", "start_date"]) {
          if (row[key] != null && row[key] is! String) return false;
        }
      }
      if (field == "service_updates" &&
          (row is! Map ||
              row["number"] is! String ||
              ![
                "cancelled",
                "diverted",
                "partially_cancelled",
              ].contains(row["status"])))
        return false;
    }
  }
  return true;
}

String responseKey(String path, double lat, double lon) =>
    "$path?lat=$lat&lon=$lon";

({Spot place, String? gateId})? parseCrossingLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null) return null;
  final q = uri.queryParameters;
  final lat = double.tryParse(q["lat"] ?? q["mlat"] ?? "");
  final lon = double.tryParse(q["lon"] ?? q["mlon"] ?? "");
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 90 ||
      lon.abs() > 180) {
    return null;
  }
  return (place: Spot(lat, lon), gateId: q["gate"]);
}

String crossingLink(Gate gate) {
  const webBase = String.fromEnvironment(
    "WEB_BASE",
    defaultValue: "https://gateahead.vercel.app/",
  );
  final base = Uri.tryParse(webBase);
  if (base != null &&
      base.hasAuthority &&
      ["http", "https"].contains(base.scheme)) {
    return base
        .replace(
          queryParameters: {
            "lat": "${gate.lat}",
            "lon": "${gate.lon}",
            "gate": gate.id,
            "name": gate.name,
          },
        )
        .toString();
  }
  return Uri.https("www.openstreetmap.org", "/", {
    "mlat": "${gate.lat}",
    "mlon": "${gate.lon}",
  }).toString();
}
