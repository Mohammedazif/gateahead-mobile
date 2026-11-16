class Spot {
  const Spot(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) =>
      other is Spot && other.lat == lat && other.lon == lon;

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
    this.closesIn,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final double km;
  final String source;
  final String? status;
  final double? eta;

  /// Estimated minutes until the barrier comes down; zero or less predicts closure.
  final double? closesIn;

  Spot get spot => Spot(lat, lon);

  Gate copyWith({String? name, String? status, double? eta, double? closesIn}) {
    return Gate(
      id: id,
      name: name ?? this.name,
      lat: lat,
      lon: lon,
      km: km,
      source: source,
      status: status ?? this.status,
      eta: eta ?? this.eta,
      closesIn: closesIn ?? this.closesIn,
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
    this.runId = "",
    this.startDate = "",
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
    this.closesIn,
    this.ageMin,
    this.basis = "",
  });

  final double? ageMin;
  final String basis;
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

  /// Estimated minutes until the barrier comes down; zero or less predicts closure. Null from an older API.
  final double? closesIn;

  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "${train}:$startDate"
      : train;

  static Approach? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final eta = _maybeNum(json["eta"]);
    if (eta == null) return null;
    return Approach(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      train: _str(json["train"]),
      name: _str(json["name"]),
      cluster: _str(json["cluster"]),
      count: _maybeNum(json["count"])?.round() ?? 0,
      eta: eta,
      status: _str(json["status"]),
      fromYouKm: _maybeNum(json["from_you_km"]) ?? 0,
      lat: _maybeNum(json["lat"]) ?? 0,
      lon: _maybeNum(json["lon"]) ?? 0,
      ids: [for (final id in (json["ids"] as List?) ?? const []) id.toString()],
      runInfo: RunInfo.parse(json),
      bracket: _str(json["bracket"]),
      closesIn: _maybeNum(json["closes_in"]),
      ageMin: _maybeNum(json["age_min"]),
      basis: _str(json["basis"]),
    );
  }
}

/// A train that went over a crossing near you in the last few minutes.
class Passed {
  const Passed({
    this.runId = "",
    this.startDate = "",
    required this.train,
    required this.name,
    required this.cluster,
    required this.ago,
    this.ids = const [],
  });

  final String train;
  final String name;
  final String cluster;
  final double ago;
  final List<String> ids;

  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "${train}:$startDate"
      : train;

  static Passed? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final ago = _maybeNum(json["ago"]);
    if (ago == null) return null;
    return Passed(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      train: _str(json["train"]),
      name: _str(json["name"]),
      cluster: _str(json["cluster"]),
      ago: ago,
      ids: [for (final id in (json["ids"] as List?) ?? const []) id.toString()],
    );
  }
}

class Sighting {
  const Sighting({
    this.runId = "",
    this.startDate = "",
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

  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "${number}:$startDate"
      : number;

  static Sighting? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    return Sighting(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      number: _str(json["number"]),
      name: _str(json["name"]),
      age: _maybeNum(json["age"]) ?? 0,
      passedLocal: json["passed_local"] == true,
      runInfo: RunInfo.parse(json),
      eta: _maybeNum(json["eta"]),
    );
  }
}

class GatePrediction {
  const GatePrediction({
    this.runId = "",
    this.startDate = "",
    required this.id,
    required this.eta,
    required this.status,
    this.closesIn,
    this.train = "",
  });
  final String id, status, train;
  final double eta;
  final double? closesIn;
  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "${train}:$startDate"
      : train;

  static GatePrediction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final eta = _maybeNum(raw["eta"]), id = raw["id"];
    if (eta == null || id is! String) return null;
    return GatePrediction(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      id: id,
      eta: eta,
      status: _str(raw["status"]),
      closesIn: _maybeNum(raw["closes_in"]),
      train: _str(raw["train"]),
    );
  }
}

class AwaitingTrain {
  const AwaitingTrain({
    this.runId = "",
    this.startDate = "",
    required this.number,
    required this.name,
    required this.current,
    required this.ageMin,
    this.ids = const [],
  });
  final String number, name, current;
  final double ageMin;
  final List<String> ids;

  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "${number}:$startDate"
      : number;

  static AwaitingTrain? tryParse(Object? raw) {
    if (raw is! Map || raw["number"] is! String) return null;
    return AwaitingTrain(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      number: raw["number"],
      name: _str(raw["name"]),
      current: _str(raw["current"]),
      ageMin: _maybeNum(raw["age_min"]) ?? 0,
      ids: [for (final id in (raw["ids"] as List?) ?? const []) id.toString()],
    );
  }
}

class TrainCoverage {
  const TrainCoverage({
    this.liveChecked = 0,
    this.liveCandidates = 0,
    this.pendingLive = 0,
    this.unavailableLive = 0,
    this.unavailableDiscovery = 0,
    this.missingOrStaleRoutes = 0,
  });

  final int liveChecked,
      liveCandidates,
      pendingLive,
      unavailableLive,
      unavailableDiscovery,
      missingOrStaleRoutes;

  String? get notice {
    if (unavailableDiscovery > 0) {
      return "Train discovery could not complete. Some services may be missing; refresh to try again.";
    }
    if (pendingLive > 0) {
      return "$liveChecked of $liveCandidates train checks completed. $pendingLive still pending; refresh to continue.";
    }
    if (missingOrStaleRoutes > 0) {
      return "Some train timetables are missing or need refreshing. Coverage is incomplete.";
    }
    if (unavailableLive > 0) {
      return "Some services have no current running report. Coverage is incomplete.";
    }
    return null;
  }

  static TrainCoverage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return TrainCoverage(
      liveChecked: _maybeNum(raw["live_checked"])?.round() ?? 0,
      liveCandidates: _maybeNum(raw["live_candidates"])?.round() ?? 0,
      pendingLive: _maybeNum(raw["pending_live"])?.round() ?? 0,
      unavailableLive: _maybeNum(raw["unavailable_live"])?.round() ?? 0,
      unavailableDiscovery:
          _maybeNum(raw["unavailable_discovery"])?.round() ?? 0,
      missingOrStaleRoutes:
          _maybeNum(raw["missing_or_stale_routes"])?.round() ?? 0,
    );
  }
}

class Predict {
  const Predict({
    this.serviceUpdates = const [],
    this.awaitingUpdate = const [],
    this.coverage,
    this.gatePredictions,
    this.error = "",
    this.crossings = 0,
    this.stations = const [],
    this.checked = 0,
    this.running = 0,
    this.approaching = const [],
    this.passed = const [],
    this.sightings = const [],
    this.offline = false,
    this.savedAt,
    this.generatedAt,
  });

  final List<GatePrediction>? gatePredictions;
  final List<AwaitingTrain> awaitingUpdate;
  final TrainCoverage? coverage;
  final List<ServiceUpdate> serviceUpdates;
  final bool offline;
  final DateTime? savedAt;
  final DateTime? generatedAt;

  final String error;
  final int crossings;
  final List<String> stations;
  final int checked;
  final int running;
  final List<Approach> approaching;
  final List<Passed> passed;
  final List<Sighting> sightings;

  static Predict parse(Map<String, dynamic> json) {
    return Predict(
      serviceUpdates: [
        for (final row in (json["service_updates"] as List?) ?? const [])
          ?ServiceUpdate.tryParse(row),
      ],
      awaitingUpdate: [
        for (final row in (json["awaiting_update"] as List?) ?? const [])
          ?AwaitingTrain.tryParse(row),
      ],
      coverage: TrainCoverage.tryParse(json["coverage"]),
      gatePredictions: json["gate_predictions"] is List
          ? [
              for (final row in json["gate_predictions"] as List)
                ?GatePrediction.tryParse(row),
            ]
          : null,
      offline: json["_offline"] == true,
      savedAt: json["_saved_at"] is int
          ? DateTime.fromMillisecondsSinceEpoch(json["_saved_at"])
          : null,
      generatedAt: DateTime.tryParse(_str(json["generated_at"])),
      error: _str(json["error"]),
      crossings: _maybeNum(json["crossings"])?.round() ?? 0,
      stations: [
        for (final code in (json["stations"] as List?) ?? const [])
          code.toString(),
      ],
      checked: _maybeNum(json["checked"])?.round() ?? 0,
      running: _maybeNum(json["running"])?.round() ?? 0,
      approaching: [
        for (final row in (json["approaching"] as List?) ?? const [])
          ?Approach.tryParse(row),
      ],
      passed: [
        for (final row in (json["passed"] as List?) ?? const [])
          ?Passed.tryParse(row),
      ],
      sightings: [
        for (final row in (json["sightings"] as List?) ?? const [])
          ?Sighting.tryParse(row),
      ],
    );
  }
}

class SceneTrain {
  const SceneTrain({
    this.runId = "",
    this.startDate = "",
    required this.number,
    required this.name,
    required this.etaMin,
    required this.status,
    required this.alongKm,
    required this.ageMin,
    this.positionOnSegment = false,
    this.bracket = "",
    this.closesInMin,
    this.movement = "",
    this.current = "",
    this.basis = "",
    this.snapshotAt,
  });

  final String movement, current, basis;
  final DateTime? snapshotAt;
  final bool positionOnSegment;
  final String number;
  final String name;
  final double etaMin;
  final String status;
  final double alongKm;
  final double ageMin;
  final String bracket;

  /// Estimated minutes until the barrier comes down; zero or less predicts closure. Null from an older API.
  final double? closesInMin;

  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "${number}:$startDate"
      : number;

  static SceneTrain? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    return SceneTrain(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      positionOnSegment: json["position_on_segment"] == true,
      number: _str(json["number"]),
      name: _str(json["name"]),
      etaMin: _maybeNum(json["eta_min"]) ?? 0,
      status: _str(json["status"]),
      alongKm: _maybeNum(json["along_km"]) ?? 0,
      ageMin: _maybeNum(json["age_min"]) ?? 0,
      bracket: _str(json["bracket"]),
      closesInMin: _maybeNum(json["closes_in_min"]),
      movement: _str(json["movement"]),
      current: _str(json["current"]),
      basis: _str(json["basis"]),
      snapshotAt: _timestamp(json["snapshot_at"]),
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
    return SceneCrossing(
      id: _str(json["id"]),
      name: _str(json["name"]),
      lat: lat,
      lon: lon,
    );
  }
}

class Scene {
  const Scene({
    this.serviceUpdates = const [],
    this.awaitingUpdate = const [],
    this.coverage,
    required this.available,
    this.error = "",
    this.crossing,
    this.rail = const [],
    this.trains = const [],
    this.passed = const [],
    this.offline = false,
    this.savedAt,
  });

  final List<ServiceUpdate> serviceUpdates;
  final bool offline;
  final List<AwaitingTrain> awaitingUpdate;
  final TrainCoverage? coverage;
  final DateTime? savedAt;

  final bool available;
  final String error;
  final SceneCrossing? crossing;
  final List<Spot> rail;
  final List<SceneTrain> trains;

  /// Trains that went over this crossing in the last few minutes.
  final List<ScenePassed> passed;

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
      serviceUpdates: [
        for (final row in (json["service_updates"] as List?) ?? const [])
          ?ServiceUpdate.tryParse(row),
      ],
      awaitingUpdate: [
        for (final row in (json["awaiting_update"] as List?) ?? const [])
          ?AwaitingTrain.tryParse(row),
      ],
      coverage: TrainCoverage.tryParse(json["coverage"]),
      offline: json["_offline"] == true,
      savedAt: json["_saved_at"] is int
          ? DateTime.fromMillisecondsSinceEpoch(json["_saved_at"])
          : null,
      available: json["available"] == true,
      error: _str(json["error"]),
      crossing: SceneCrossing.tryParse(json["crossing"]),
      rail: rail,
      trains: [
        for (final row in (json["trains"] as List?) ?? const [])
          ?SceneTrain.tryParse(row),
      ],
      passed: [
        for (final row in (json["passed"] as List?) ?? const [])
          ?ScenePassed.tryParse(row),
      ],
    );
  }
}

class ScenePassed {
  const ScenePassed({
    this.runId = "",
    this.startDate = "",
    required this.number,
    required this.name,
    required this.agoMin,
  });

  final String number;
  final String name;
  final double agoMin;

  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "${number}:$startDate"
      : number;

  static ScenePassed? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final ago = _maybeNum(json["ago_min"]);
    if (ago == null) return null;
    return ScenePassed(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      number: _str(json["number"]),
      name: _str(json["name"]),
      agoMin: ago,
    );
  }
}

class GatesBody {
  const GatesBody({
    required this.gates,
    this.error = "",
    this.offline = false,
    this.savedAt,
  });

  final bool offline;
  final DateTime? savedAt;

  final List<Gate> gates;
  final String error;

  static GatesBody parse(Map<String, dynamic> json) {
    return GatesBody(
      offline: json["_offline"] == true,
      savedAt: json["_saved_at"] is int
          ? DateTime.fromMillisecondsSinceEpoch(json["_saved_at"])
          : null,
      error: _str(json["error"]),
      gates: [
        for (final row in (json["gates"] as List?) ?? const [])
          ?Gate.tryParse(row),
      ],
    );
  }
}

Map<String, dynamic> _map(Map raw) {
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

String _str(Object? value) => value == null ? "" : value.toString();

double? _maybeNum(Object? value) {
  final number = switch (value) {
    num value => value.toDouble(),
    String value => double.tryParse(value),
    _ => null,
  };
  return number?.isFinite == true ? number : null;
}

DateTime? _timestamp(Object? value) {
  final seconds = _maybeNum(value);
  if (seconds == null || !seconds.isFinite) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

class ServiceUpdate {
  const ServiceUpdate({
    required this.number,
    required this.startDate,
    required this.status,
  });
  final String number, startDate, status;
  String get identity => startDate.isEmpty ? number : "$number:$startDate";
  static ServiceUpdate? tryParse(Object? raw) {
    if (raw is! Map || raw["number"] is! String) return null;
    return ServiceUpdate(
      number: raw["number"],
      startDate: _str(raw["start_date"]),
      status: _str(raw["status"]),
    );
  }
}
