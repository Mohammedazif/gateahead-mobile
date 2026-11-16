import "dart:convert";

import "package:http/http.dart" as http;

import "models.dart";
import "device_store.dart";

const defaultApiBase = String.fromEnvironment(
  "API_BASE",
  defaultValue: "http://127.0.0.1:8000",
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

  @override
  Future<List<CityHit>> cities(String query) async {
    final json = await _get("/cities", {
      "q": query,
    }, const Duration(seconds: 15));
    final rows = json["cities"];
    if (rows is! List) return const [];
    final cities = <CityHit>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = row["name"]?.toString().trim() ?? "";
      final state = row["state"]?.toString().trim() ?? "";
      final lat = row["lat"];
      final lon = row["lon"];
      if (name.isEmpty || lat is! num || lon is! num) continue;
      cities.add(
        CityHit(
          name: name,
          state: state,
          lat: lat.toDouble(),
          lon: lon.toDouble(),
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
    }, const Duration(seconds: 40));
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
    return (body["reports"] as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> report(Gate gate, String state) async {
    final id = await storage?.installationId();
    if (id == null) {
      throw RailException("Reports are unavailable on this device.");
    }
    final root = base.endsWith("/") ? base.substring(0, base.length - 1) : base;
    final response = await _client
        .post(
          Uri.parse("$root/reports"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "crossing_id": gate.id,
            "installation_id": id,
            "state": state,
            "lat": gate.lat,
            "lon": gate.lon,
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      throw RailException(
        response.statusCode == 429
            ? "Too many reports. Try again in a few minutes."
            : "Could not send your report. Try again later.",
      );
    }
    final body = jsonDecode(response.body) as Map;
    return (body["reports"] as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

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
    if (pending != null) pending.count++;
    try {
      return await _getResponse(path, query, timeout, pending, version);
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
  ) async {
    final root = base.endsWith("/") ? base.substring(0, base.length - 1) : base;
    final uri = Uri.parse("$root$path").replace(queryParameters: query);
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
        (latestPrediction == null || !saved.at.isBefore(latestPrediction.at)) &&
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
          int.tryParse(response.headers["retry-after"] ?? "") ?? 600;
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
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (saved != null) return saved.restored();
      throw RailException(
        "The service returned invalid data. Try again in a moment.",
      );
    }
    if (decoded is! Map) {
      if (saved != null) return saved.restored();
      throw RailException(
        "Could not reach the service at $base. Try again in a moment.",
      );
    }
    final data = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (cacheable && !validResponseBody(path, data)) {
      if (saved != null) return saved.restored();
      throw RailException(
        "The service returned invalid data. Try again in a moment.",
      );
    }
    if (cacheable &&
        saved != null &&
        data["error"] != null &&
        data["error"] != "") {
      return saved.restored();
    }
    if (cacheable && (data["error"] == null || data["error"] == "")) {
      var at = DateTime.now();
      if (pending != null && version >= pending.storedVersion) {
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
