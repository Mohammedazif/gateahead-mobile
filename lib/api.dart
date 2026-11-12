import "dart:convert";

import "package:http/http.dart" as http;

import "models.dart";

const defaultApiBase = String.fromEnvironment("API_BASE", defaultValue: "http://127.0.0.1:8000");

class RailException implements Exception {
  RailException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class RailApi {
  Future<String?> placeName(double lat, double lon);

  Future<GatesBody> gates(double lat, double lon);

  Future<Predict> predict(double lat, double lon);

  Future<Scene> scene(double lat, double lon, String crossingId);
}

class HttpRailApi implements RailApi {
  HttpRailApi({required this.base, http.Client? client}) : _client = client ?? http.Client();

  final String base;
  final http.Client _client;

  @override
  Future<String?> placeName(double lat, double lon) async {
    final json = await _get("/place", {"lat": "$lat", "lon": "$lon"}, const Duration(seconds: 20));
    final name = json["name"];
    if (name == null) return null;
    final text = name.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  Future<GatesBody> gates(double lat, double lon) async {
    final json = await _get("/gates", {"lat": "$lat", "lon": "$lon"}, const Duration(seconds: 40));
    return GatesBody.parse(json);
  }

  @override
  Future<Predict> predict(double lat, double lon) async {
    final json = await _get("/predict", {"lat": "$lat", "lon": "$lon"}, const Duration(seconds: 90));
    return Predict.parse(json);
  }

  @override
  Future<Scene> scene(double lat, double lon, String crossingId) async {
    final json = await _get(
      "/scene",
      {"lat": "$lat", "lon": "$lon", "crossing_id": crossingId},
      const Duration(seconds: 90),
    );
    return Scene.parse(json);
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query, Duration timeout) async {
    final root = base.endsWith("/") ? base.substring(0, base.length - 1) : base;
    final uri = Uri.parse("$root$path").replace(queryParameters: query);
    late http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } catch (_) {
      throw RailException("Could not reach the service at $base. Try again in a moment.");
    }
    if (response.statusCode == 429) {
      throw RailException("Too many checks. Wait a few minutes and try again.");
    }
    if (response.statusCode != 200) {
      throw RailException("Could not reach the service at $base. Try again in a moment.");
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw RailException("Could not reach the service at $base. Try again in a moment.");
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
