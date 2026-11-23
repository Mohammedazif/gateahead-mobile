import "dart:convert";

import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;

import "models.dart";
import "device_store.dart";

const defaultApiBase = String.fromEnvironment(
  "API_BASE",
  defaultValue: kReleaseMode
      ? "https://gateahead-api.onrender.com"
      : "http://127.0.0.1:8000",
);

class RailException implements Exception {
  RailException(this.message, {this.retryAt});

  final DateTime? retryAt;

  final String message;

  @override
  String toString() => message;
}

class CityHit {
  const CityHit({
    required this.name,
    required this.state,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String state;
  final double lat;
  final double lon;
}

abstract class RailApi {
  Future<List<CityHit>> cities(String query);

  Future<String?> placeName(double lat, double lon);

  Future<GatesBody> gates(double lat, double lon);

  Future<Predict> predict(double lat, double lon);

  Future<Scene> scene(double lat, double lon, String crossingId);
}

abstract class CommunityApi {
  Future<List<Map<String, dynamic>>> reports(String id);
  Future<List<Map<String, dynamic>>> report(Gate gate, String state);
}

class HttpRailApi implements RailApi, CommunityApi {
  HttpRailApi({required this.base, http.Client? client, this.storage})
    : _client = client ?? http.Client();

  final String base;
  final DeviceStore? storage;
  final http.Client _client;
  final Map<String, _CacheWrites> _cacheWrites = {};
  int _requestVersion = 0;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.tryParse(base);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != "https" && (kReleaseMode || uri.scheme != "http"))) {
      throw RailException(
        kReleaseMode
            ? "This app requires an HTTPS service address."
            : "The service address is invalid.",
      );
    }
    final prefix = uri.path.endsWith("/")
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: "$prefix$path", queryParameters: query);
  }

  @override
  Future<List<CityHit>> cities(String query) async {
    final json = await _get("/cities", {
      "q": query,
    }, const Duration(seconds: 15));
    final rows = json["cities"];
    if (rows is! List) {
      throw RailException("City search returned invalid data. Try again.");
    }
    final cities = <CityHit>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = row["name"] is String ? (row["name"] as String).trim() : "";
      final state = row["state"] is String
          ? (row["state"] as String).trim()
          : "";
      final lat = row["lat"];
      final lon = row["lon"];
      if (name.isEmpty || !validCoordinates(lat, lon)) continue;
      cities.add(
        CityHit(
          name: name,
          state: state,
          lat: (lat as num).toDouble(),
          lon: (lon as num).toDouble(),
        ),
      );
    }
    return cities;
  }

  @override
  Future<String?> placeName(double lat, double lon) async {
    final json = await _get("/place", {
      "lat": "$lat",
      "lon": "$lon",
    }, const Duration(seconds: 20));
    final name = json["name"];
    if (name == null) return null;
    final text = name.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  Future<GatesBody> gates(double lat, double lon) async {
    final json = await _get("/gates", {
      "lat": "$lat",
      "lon": "$lon",
    }, const Duration(seconds: 90));
    return GatesBody.parse(json);
  }

  @override
  Future<Predict> predict(double lat, double lon) async {
    final json = await _get("/predict", {
      "lat": "$lat",
      "lon": "$lon",
    }, const Duration(seconds: 90));
    return Predict.parse(json);
  }

  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async {
    final json = await _get("/scene", {
      "lat": "$lat",
      "lon": "$lon",
      "crossing_id": crossingId,
    }, const Duration(seconds: 90));
    return Scene.parse(json);
  }

  @override
  Future<List<Map<String, dynamic>>> reports(String id) async {
    final body = await _get("/reports", {
      "crossing_id": id,
    }, const Duration(seconds: 15));
    return _reports(body);
  }

  @override
  Future<List<Map<String, dynamic>>> report(Gate gate, String state) async {
    if (isLegacyCrossingId(gate.id)) {
      throw RailException("Reopen this crossing to update its saved link.");
    }
    final id = await storage?.installationId();
    if (id == null) {
      throw RailException("Reports are unavailable on this device.");
    }
    final uri = _uri("/reports");
    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "crossing_id": gate.id,
              "installation_id": id,
              "state": state,
              "lat": gate.lat,
              "lon": gate.lon,
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw RailException("Could not send your report. Try again.");
    }
    if (response.statusCode != 200) {
      throw RailException(
        response.statusCode == 429
            ? "Too many reports. Try again in a few minutes."
            : "Could not send your report. Try again later.",
      );
    }
    late Map<String, dynamic> body;
    try {
      body = _decode(response.body);
    } on FormatException {
      throw RailException("The service returned an invalid report. Try again.");
    }
    final reports = _reports(body);
    if (!reports.any((row) => row["state"] == state)) {
      throw RailException(
        "The service did not confirm your report. Try again.",
      );
    }
    return reports;
  }

  static Map<String, dynamic> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    return decoded;
  }

  static List<Map<String, dynamic>> _reports(Map<String, dynamic> body) {
    final rows = body["reports"];
    if (body["error"] != null || body["verified"] != false || rows is! List) {
      throw RailException("The service returned an invalid report. Try again.");
    }
    final reports = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          !const ["open", "closed", "wrong_location"].contains(row["state"]) ||
          !_validReportTime(row["at"]) ||
          !_validReportTime(row["expires_at"]) ||
          (row["expires_at"] as num) <= (row["at"] as num)) {
        throw RailException(
          "The service returned an invalid report. Try again.",
        );
      }
      reports.add(row);
    }
    return reports;
  }

  static bool _validReportTime(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 8640000000000;

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
    Duration timeout,
  ) async {
    final key = Uri(path: path, queryParameters: query).toString();
    final pending = ["/gates", "/predict", "/scene"].contains(path)
        ? _cacheWrites.putIfAbsent(key, _CacheWrites.new)
        : null;
    final version = ++_requestVersion;
    final historyGeneration = storage?.historyGeneration;
    if (pending != null) pending.count++;
    try {
      return await _getResponse(
        path,
        query,
        timeout,
        pending,
        version,
        historyGeneration,
      );
    } finally {
      if (pending != null && --pending.count == 0) _cacheWrites.remove(key);
    }
  }

  Future<Map<String, dynamic>> _getResponse(
    String path,
    Map<String, String> query,
    Duration timeout,
    _CacheWrites? pending,
    int version,
    int? historyGeneration,
  ) async {
    final uri = _uri(path, query);
    final cacheable = ["/gates", "/predict", "/scene"].contains(path);
    final key = Uri(path: path, queryParameters: query).toString();
    final saved = cacheable ? storage?.response(key) : null;
    final predictionKey = Uri(
      path: "/predict",
      queryParameters: {"lat": query["lat"] ?? "", "lon": query["lon"] ?? ""},
    ).toString();
    final latestPrediction = path == "/scene"
        ? storage?.response(predictionKey)
        : null;
    if (path == "/scene" &&
        saved != null &&
        saved.data["available"] == true &&
        saved.data["map_warning"] == null &&
        TrainCoverage.tryParse(saved.data["coverage"])?.incomplete != true &&
        (latestPrediction == null || !saved.at.isBefore(latestPrediction.at)) &&
        !saved.at.isAfter(DateTime.now()) &&
        DateTime.now().difference(saved.at).inSeconds < 90) {
      return {...saved.data, "_saved_at": saved.at.millisecondsSinceEpoch};
    }
    final pausedUntil = storedDateTime(storage?.read("paused-until"));
    if (["/predict", "/scene"].contains(path) &&
        pausedUntil != null &&
        pausedUntil.isAfter(DateTime.now())) {
      if (saved != null) return saved.restored();
      throw RailException(
        "Checks are paused. Try again in a few minutes.",
        retryAt: pausedUntil,
      );
    }
    late http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } catch (_) {
      if (saved != null) return saved.restored();
      throw RailException(
        "Could not reach the service at $base. Try again in a moment.",
      );
    }
    if (response.statusCode == 429) {
      final seconds =
          (int.tryParse(response.headers["retry-after"] ?? "") ?? 600).clamp(
            1,
            86400,
          );
      if (path != "/predict" && path != "/scene") {
        throw RailException("Too many requests. Try again in a few minutes.");
      }
      await storage?.write(
        "paused-until",
        DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch,
      );
      throw RailException(
        "Too many checks. Automatic checks are paused; try again in a few minutes.",
        retryAt: DateTime.now().add(Duration(seconds: seconds)),
      );
    }
    if (response.statusCode != 200) {
      if (saved != null && response.statusCode >= 500) return saved.restored();
      throw RailException(
        "Could not reach the service at $base. Try again in a moment.",
      );
    }
    late Map<String, dynamic> data;
    try {
      data = _decode(response.body)
        ..remove("_offline")
        ..remove("_saved_at");
    } on FormatException {
      if (saved != null) return saved.restored();
      throw RailException(
        "The service returned invalid data. Try again in a moment.",
      );
    }
    if (cacheable &&
        !validResponseBody(path, data, crossingId: query["crossing_id"])) {
      if (saved != null) return saved.restored();
      throw RailException(
        "The service returned invalid data. Try again in a moment.",
      );
    }
    if (cacheable &&
        saved != null &&
        data["error"] != null &&
        data["error"] != "crossing_not_found" &&
        !(path == "/scene" && data["legacy_alias_resolved"] == true) &&
        data["error"] != "") {
      return saved.restored();
    }
    if (cacheable && (data["error"] == null || data["error"] == "")) {
      var at = DateTime.now();
      final degraded =
          (data["map_warning"] as String?)?.isNotEmpty == true ||
          TrainCoverage.tryParse(data["coverage"])?.incomplete == true;
      if (pending != null &&
          version >= pending.storedVersion &&
          historyGeneration == storage?.historyGeneration &&
          !degraded &&
          (path != "/scene" || data["available"] == true)) {
        pending.storedVersion = version;
        at = await storage?.saveResponse(key, data) ?? at;
      }
      return {...data, "_saved_at": at.millisecondsSinceEpoch};
    }
    return data;
  }
}

class _CacheWrites {
  int count = 0;
  int storedVersion = 0;
}
