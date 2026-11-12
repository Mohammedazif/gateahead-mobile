class Spot {
  const Spot(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is Spot && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);
}

class Gate {
  const Gate({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.km,
    required this.source,
    this.status,
    this.eta,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final double km;
  final String source;
  final String? status;
  final double? eta;

  Spot get spot => Spot(lat, lon);

  Gate copyWith({String? name, String? status, double? eta}) {
    return Gate(
      id: id,
      name: name ?? this.name,
      lat: lat,
      lon: lon,
      km: km,
      source: source,
      status: status ?? this.status,
      eta: eta ?? this.eta,
    );
  }

  static Gate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final lat = _maybeNum(json["lat"]);
    final lon = _maybeNum(json["lon"]);
    if (lat == null || lon == null) return null;
    return Gate(
      id: _str(json["id"]),
      name: _str(json["name"]),
      lat: lat,
      lon: lon,
      km: _maybeNum(json["km"]) ?? 0,
      source: _str(json["source"]),
    );
  }
}

class RunInfo {
  const RunInfo({
    this.current = "",
    this.atStation = false,
    this.origin = "",
    this.dest = "",
    this.nextStop = "",
    this.nextIn = "",
    this.departedAt = "",
    this.scheduledAt = "",
    this.platform = "",
    this.leftKm,
    this.run = "",
    this.delay = 0,
  });

  final String current;
  final bool atStation;
  final String origin;
  final String dest;
  final String nextStop;
  final String nextIn;
  final String departedAt;
  final String scheduledAt;
  final String platform;
  final double? leftKm;
  final String run;
  final int delay;

  static RunInfo parse(Map<String, dynamic> json) {
    return RunInfo(
      current: _str(json["current"]),
      atStation: json["at_station"] == true,
      origin: _str(json["origin"]),
      dest: _str(json["dest"]),
      nextStop: _str(json["next"]),
      nextIn: _str(json["next_in"]),
      departedAt: _str(json["departed_at"]),
      scheduledAt: _str(json["scheduled_at"]),
      platform: _str(json["platform"]),
      leftKm: _maybeNum(json["left_km"]),
      run: _str(json["run"]),
      delay: _maybeNum(json["delay"])?.round() ?? 0,
    );
  }
}

class Approach {
  const Approach({
    required this.train,
    required this.name,
    required this.cluster,
    required this.count,
    required this.eta,
    required this.status,
    required this.fromYouKm,
    required this.lat,
    required this.lon,
    required this.ids,
    required this.runInfo,
    this.bracket = "",
  });

  final String train;
  final String name;
  final String cluster;
  final int count;
  final double eta;
  final String status;
  final double fromYouKm;
  final double lat;
  final double lon;
  final List<String> ids;
  final RunInfo runInfo;
  final String bracket;

  static Approach? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final eta = _maybeNum(json["eta"]);
    if (eta == null) return null;
    return Approach(
      train: _str(json["train"]),
      name: _str(json["name"]),
      cluster: _str(json["cluster"]),
      count: _maybeNum(json["count"])?.round() ?? 0,
      eta: eta,
      status: _str(json["status"]),
      fromYouKm: _maybeNum(json["from_you_km"]) ?? 0,
      lat: _maybeNum(json["lat"]) ?? 0,
      lon: _maybeNum(json["lon"]) ?? 0,
      ids: [
        for (final id in (json["ids"] as List?) ?? const []) id.toString(),
      ],
      runInfo: RunInfo.parse(json),
      bracket: _str(json["bracket"]),
    );
  }
}

class Sighting {
  const Sighting({
    required this.number,
    required this.name,
    required this.age,
    required this.passedLocal,
    required this.runInfo,
    this.eta,
  });

  final String number;
  final String name;
  final double age;
  final bool passedLocal;
  final RunInfo runInfo;
  final double? eta;

  static Sighting? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    return Sighting(
      number: _str(json["number"]),
      name: _str(json["name"]),
      age: _maybeNum(json["age"]) ?? 0,
      passedLocal: json["passed_local"] == true,
      runInfo: RunInfo.parse(json),
      eta: _maybeNum(json["eta"]),
    );
  }
}

class Predict {
  const Predict({
    this.error = "",
    this.crossings = 0,
    this.stations = const [],
    this.checked = 0,
    this.running = 0,
    this.approaching = const [],
    this.sightings = const [],
  });

  final String error;
  final int crossings;
  final List<String> stations;
  final int checked;
  final int running;
  final List<Approach> approaching;
  final List<Sighting> sightings;

  static Predict parse(Map<String, dynamic> json) {
    return Predict(
      error: _str(json["error"]),
      crossings: _maybeNum(json["crossings"])?.round() ?? 0,
      stations: [
        for (final code in (json["stations"] as List?) ?? const []) code.toString(),
      ],
      checked: _maybeNum(json["checked"])?.round() ?? 0,
      running: _maybeNum(json["running"])?.round() ?? 0,
      approaching: [
        for (final row in (json["approaching"] as List?) ?? const []) ?Approach.tryParse(row),
      ],
      sightings: [
        for (final row in (json["sightings"] as List?) ?? const []) ?Sighting.tryParse(row),
      ],
    );
  }
}

class SceneTrain {
  const SceneTrain({
    required this.number,
    required this.name,
    required this.etaMin,
    required this.status,
    required this.alongKm,
    required this.ageMin,
    this.bracket = "",
  });

  final String number;
  final String name;
  final double etaMin;
  final String status;
  final double alongKm;
  final double ageMin;
  final String bracket;

  static SceneTrain? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    return SceneTrain(
      number: _str(json["number"]),
      name: _str(json["name"]),
      etaMin: _maybeNum(json["eta_min"]) ?? 0,
      status: _str(json["status"]),
      alongKm: _maybeNum(json["along_km"]) ?? 0,
      ageMin: _maybeNum(json["age_min"]) ?? 0,
      bracket: _str(json["bracket"]),
    );
  }
}

class SceneCrossing {
  const SceneCrossing({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  static SceneCrossing? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final lat = _maybeNum(json["lat"]);
    final lon = _maybeNum(json["lon"]);
    if (lat == null || lon == null) return null;
    return SceneCrossing(id: _str(json["id"]), name: _str(json["name"]), lat: lat, lon: lon);
  }
}

class Scene {
  const Scene({
    required this.available,
    this.error = "",
    this.crossing,
    this.rail = const [],
    this.trains = const [],
  });

  final bool available;
  final String error;
  final SceneCrossing? crossing;
  final List<Spot> rail;
  final List<SceneTrain> trains;

  static Scene parse(Map<String, dynamic> json) {
    final rail = <Spot>[];
    for (final point in (json["rail"] as List?) ?? const []) {
      if (point is! List || point.length < 2) continue;
      final lat = _maybeNum(point[0]);
      final lon = _maybeNum(point[1]);
      if (lat == null || lon == null) continue;
      rail.add(Spot(lat, lon));
    }
    return Scene(
      available: json["available"] == true,
      error: _str(json["error"]),
      crossing: SceneCrossing.tryParse(json["crossing"]),
      rail: rail,
      trains: [
        for (final row in (json["trains"] as List?) ?? const []) ?SceneTrain.tryParse(row),
      ],
    );
  }
}

class GatesBody {
  const GatesBody({required this.gates, this.error = ""});

  final List<Gate> gates;
  final String error;

  static GatesBody parse(Map<String, dynamic> json) {
    return GatesBody(
      error: _str(json["error"]),
      gates: [
        for (final row in (json["gates"] as List?) ?? const []) ?Gate.tryParse(row),
      ],
    );
  }
}

Map<String, dynamic> _map(Map raw) {
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

String _str(Object? value) => value == null ? "" : value.toString();

double? _maybeNum(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
