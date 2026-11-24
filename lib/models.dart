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
    this.groupId = "",
    this.groupName = "",
    this.groupSize = 1,
    this.road = "",
    this.area = "",
    this.status,
    this.eta,
    this.closesIn,
    this.hasUncertainTrain = false,
    this.earlierEstimate = false,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final double km;
  final String source;

  /// Explicit same-road grouping from the crossing catalogue. Raw IDs stay distinct.
  final String groupId, groupName, road, area;
  final int groupSize;
  final String? status;
  final double? eta;
  final bool hasUncertainTrain;
  final bool earlierEstimate;

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
      groupId: groupId,
      groupName: groupName,
      groupSize: groupSize,
      road: road,
      area: area,
      status: status ?? this.status,
      eta: eta ?? this.eta,
      closesIn: closesIn ?? this.closesIn,
      hasUncertainTrain: hasUncertainTrain,
      earlierEstimate: earlierEstimate,
    );
  }

  static Gate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    if (json["restricted_freight"] == true) return null;
    final lat = _maybeNum(json["lat"]);
    final lon = _maybeNum(json["lon"]);
    final id = json["id"];
    if (id is! String ||
        id.isEmpty ||
        lat == null ||
        lat.abs() > 90 ||
        lon == null ||
        lon.abs() > 180) {
      return null;
    }
    return Gate(
      id: id,
      name: _str(json["name"]),
      lat: lat,
      lon: lon,
      km: _maybeNum(json["km"]) ?? 0,
      source: _str(json["source"]),
      groupId: json["group_id"] is String ? json["group_id"] : "",
      groupName: json["group_name"] is String ? json["group_name"] : "",
      groupSize: json["group_size"] is int && json["group_size"] > 0
          ? json["group_size"]
          : 1,
      road: json["road"] is String ? json["road"] : "",
      area: json["area"] is String ? json["area"] : "",
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
    this.observed,
  });

  final double? ageMin;
  final String basis;
  final bool? observed;
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
      ? "$train:$startDate"
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
      observed: json["observed"] is bool ? json["observed"] : null,
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
      ? "$train:$startDate"
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
      ? "$number:$startDate"
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
    this.earlierEstimate = false,
  });
  final String id, status, train;
  final double eta;
  final double? closesIn;
  final bool earlierEstimate;
  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "$train:$startDate"
      : train;

  GatePrediction asEarlierEstimate() => GatePrediction(
    id: id,
    eta: eta,
    status: status,
    closesIn: closesIn,
    train: train,
    runId: runId,
    startDate: startDate,
    earlierEstimate: true,
  );

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
    this.reason = "stopped_report",
    this.ids = const [],
  });
  final String number, name, current, reason;
  final double ageMin;
  final List<String> ids;

  final String runId, startDate;
  String get identity => runId.isNotEmpty
      ? runId
      : startDate.isNotEmpty
      ? "$number:$startDate"
      : number;

  static AwaitingTrain? tryParse(Object? raw) {
    if (raw is! Map || raw["number"] is! String || raw["number"] == "") {
      return null;
    }
    return AwaitingTrain(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      number: raw["number"],
      name: _str(raw["name"]),
      current: _str(raw["current"]),
      ageMin: _maybeNum(raw["age_min"]) ?? 0,
      reason: raw["reason"] is String ? raw["reason"] : "stopped_report",
      ids: [for (final id in (raw["ids"] as List?) ?? const []) id.toString()],
    );
  }
}

class TrainCoverage {
  const TrainCoverage({
    this.status = "",
    this.liveChecked = 0,
    this.liveCandidates = 0,
    this.pendingLive = 0,
    this.unavailableLive = 0,
    this.unavailableDiscovery = 0,
    this.missingOrStaleRoutes = 0,
  });

  final String status;
  final int liveChecked,
      liveCandidates,
      pendingLive,
      unavailableLive,
      unavailableDiscovery,
      missingOrStaleRoutes;

  bool get incomplete =>
      status == "partial" ||
      pendingLive > 0 ||
      unavailableLive > 0 ||
      unavailableDiscovery > 0 ||
      missingOrStaleRoutes > 0;

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
    return incomplete ? "Coverage is incomplete. Refresh to try again." : null;
  }

  static TrainCoverage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return TrainCoverage(
      status: raw["status"] is String ? raw["status"] : "",
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
    this.mapWarning = "",
    this.mapAgeSeconds,
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
  final String mapWarning;
  final double? mapAgeSeconds;
  bool get incomplete => mapWarning.isNotEmpty || coverage?.incomplete == true;
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
      mapWarning: _str(json["map_warning"]),
      mapAgeSeconds: _maybeNum(json["map_age_seconds"]),
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
    this.observed,
  });

  final String movement, current, basis;
  final DateTime? snapshotAt;
  final bool? observed;
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
      ? "$number:$startDate"
      : number;

  static SceneTrain? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final number = json["number"], status = json["status"];
    final eta = _maybeNum(json["eta_min"]);
    final along = _maybeNum(json["along_km"]);
    final age = _maybeNum(json["age_min"]);
    if (number is! String ||
        number.isEmpty ||
        status is! String ||
        !const [
          "closed",
          "closing_soon",
          "approaching",
          "later",
        ].contains(status) ||
        eta == null ||
        along == null ||
        along < 0 ||
        age == null ||
        age < 0 ||
        (json["snapshot_at"] != null &&
            _timestamp(json["snapshot_at"]) == null)) {
      return null;
    }
    return SceneTrain(
      runId: _str(raw["run_id"]),
      startDate: _str(raw["start_date"]),
      positionOnSegment: json["position_on_segment"] == true,
      number: number,
      name: _str(json["name"]),
      etaMin: eta,
      status: status,
      alongKm: along,
      ageMin: age,
      bracket: _str(json["bracket"]),
      closesInMin: _maybeNum(json["closes_in_min"]),
      movement: _str(json["movement"]),
      current: _str(json["current"]),
      basis: _str(json["basis"]),
      snapshotAt: _timestamp(json["snapshot_at"]),
      observed: json["observed"] is bool ? json["observed"] : null,
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
    final id = json["id"];
    if (id is! String ||
        id.isEmpty ||
        lat == null ||
        lat.abs() > 90 ||
        lon == null ||
        lon.abs() > 180) {
      return null;
    }
    return SceneCrossing(id: id, name: _str(json["name"]), lat: lat, lon: lon);
  }
}

enum RoadAccess {
  allowed,
  restricted,
  unknown;

  static RoadAccess parse(Object? value) => switch (value) {
    "allowed" => allowed,
    "restricted" => restricted,
    _ => unknown,
  };
}

class CrossingBypass {
  const CrossingBypass(
    this.kind,
    this.name,
    this.place,
    this.verifiedOn, {
    this.replacement = false,
  });

  final String kind, name, verifiedOn;
  final Spot place;
  final bool replacement;

  static CrossingBypass? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw["kind"], name = raw["name"], date = raw["verified_on"];
    final lat = _maybeNum(raw["lat"]), lon = _maybeNum(raw["lon"]);
    if ((kind != "flyover" && kind != "underpass") ||
        name is! String ||
        name.trim().isEmpty ||
        !_verifiedDate(date) ||
        lat == null ||
        lat.abs() > 90 ||
        lon == null ||
        lon.abs() > 180) {
      return null;
    }
    return CrossingBypass(
      kind,
      name.trim(),
      Spot(lat, lon),
      date as String,
      replacement: raw["replacement"] == true,
    );
  }

  static bool _verifiedDate(Object? value) {
    if (value is! String || !RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(value)) {
      return false;
    }
    return DateTime.tryParse(value)
            ?.toIso8601String()
            .startsWith("${value}T") ??
        false;
  }
}

class CrossingAccess {
  const CrossingAccess({
    required this.cars,
    required this.twoWheelers,
    required this.pedestrians,
    required this.verifiedOn,
    required this.bypasses,
    this.source = "mapped",
  });

  final RoadAccess cars, twoWheelers, pedestrians;
  final String? verifiedOn;
  final List<CrossingBypass> bypasses;
  final String source;

  static bool _currentVerification(String? value, DateTime now) {
    if (!CrossingBypass._verifiedDate(value)) return false;
    final india = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final today = DateTime.utc(india.year, india.month, india.day);
    final age = today.difference(DateTime.parse("${value}T00:00:00Z")).inDays;
    return age >= 0 && age <= 365;
  }

  CrossingAccess current(DateTime now) {
    final valid =
        source == "mapped" ||
        source == "verified" && _currentVerification(verifiedOn, now);
    return CrossingAccess(
      cars: valid ? cars : RoadAccess.unknown,
      twoWheelers: valid ? twoWheelers : RoadAccess.unknown,
      pedestrians: valid ? pedestrians : RoadAccess.unknown,
      source: valid ? source : "unavailable",
      verifiedOn: valid ? verifiedOn : null,
      bypasses: [
        for (final bypass in bypasses)
          if (_currentVerification(bypass.verifiedOn, now)) bypass,
      ],
    );
  }

  static CrossingAccess? tryParse(Object? raw) {
    if (raw is! Map ||
        !const ["mapped", "verified", "unavailable"].contains(raw["source"])) {
      return null;
    }
    final date = raw["verified_on"];
    final bypasses = raw["bypasses"];
    return CrossingAccess(
      cars: RoadAccess.parse(raw["cars"]),
      twoWheelers: RoadAccess.parse(raw["two_wheelers"]),
      pedestrians: RoadAccess.parse(raw["pedestrians"]),
      source: raw["source"] as String,
      verifiedOn:
          raw["source"] == "verified" && CrossingBypass._verifiedDate(date)
          ? date as String
          : null,
      bypasses: [
        if (bypasses is List)
          for (final bypass in bypasses) ?CrossingBypass.tryParse(bypass),
      ],
    );
  }
}

class CrossingDetails {
  const CrossingDetails({
    required this.crossing,
    required this.access,
    required this.aliasResolved,
    required this.mapWarning,
  });

  final SceneCrossing crossing;
  final CrossingAccess access;
  final bool aliasResolved;
  final String mapWarning;
}

class Scene {
  const Scene({
    this.serviceUpdates = const [],
    this.awaitingUpdate = const [],
    this.coverage,
    required this.available,
    this.error = "",
    this.mapWarning = "",
    this.mapAgeSeconds,
    this.crossing,
    this.crossingAccess,
    this.rail = const [],
    this.trains = const [],
    this.passed = const [],
    this.offline = false,
    this.savedAt,
    this.legacyAliasResolved = false,
  });

  final List<ServiceUpdate> serviceUpdates;
  final bool offline;
  final bool legacyAliasResolved;
  final List<AwaitingTrain> awaitingUpdate;
  final TrainCoverage? coverage;
  final DateTime? savedAt;

  final bool available;
  final String error;
  final String mapWarning;
  final double? mapAgeSeconds;
  bool get incomplete => mapWarning.isNotEmpty || coverage?.incomplete == true;
  final SceneCrossing? crossing;
  final CrossingAccess? crossingAccess;
  final List<Spot> rail;
  final List<SceneTrain> trains;

  /// Trains that went over this crossing in the last few minutes.
  final List<ScenePassed> passed;

  Scene asSaved() => Scene(
    serviceUpdates: serviceUpdates,
    awaitingUpdate: awaitingUpdate,
    coverage: coverage,
    available: available,
    error: error,
    mapWarning: mapWarning,
    mapAgeSeconds: mapAgeSeconds,
    crossing: crossing,
    crossingAccess: crossingAccess,
    rail: rail,
    trains: trains,
    passed: passed,
    offline: true,
    savedAt: savedAt,
    legacyAliasResolved: legacyAliasResolved,
  );

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
      legacyAliasResolved: json["legacy_alias_resolved"] == true,
      savedAt: json["_saved_at"] is int
          ? DateTime.fromMillisecondsSinceEpoch(json["_saved_at"])
          : null,
      available: json["available"] == true,
      error: _str(json["error"]),
      mapWarning: _str(json["map_warning"]),
      mapAgeSeconds: _maybeNum(json["map_age_seconds"]),
      crossing: SceneCrossing.tryParse(json["crossing"]),
      crossingAccess: CrossingAccess.tryParse(json["crossing_access"]),
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
      ? "$number:$startDate"
      : number;

  static ScenePassed? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = _map(raw);
    final ago = _maybeNum(json["ago_min"]);
    if (ago == null ||
        ago < 0 ||
        json["number"] is! String ||
        json["number"] == "") {
      return null;
    }
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
    this.mapWarning = "",
    this.mapAgeSeconds,
    this.offline = false,
    this.savedAt,
  });

  final bool offline;
  final DateTime? savedAt;

  final List<Gate> gates;
  final String error;
  final String mapWarning;
  final double? mapAgeSeconds;
  bool get authoritative => !offline && error.isEmpty && mapWarning.isEmpty;

  static GatesBody parse(Map<String, dynamic> json) {
    return GatesBody(
      offline: json["_offline"] == true,
      savedAt: json["_saved_at"] is int
          ? DateTime.fromMillisecondsSinceEpoch(json["_saved_at"])
          : null,
      error: _str(json["error"]),
      mapWarning: _str(json["map_warning"]),
      mapAgeSeconds: _maybeNum(json["map_age_seconds"]),
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
  if (seconds == null || seconds.abs() > 8640000000000) return null;
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
