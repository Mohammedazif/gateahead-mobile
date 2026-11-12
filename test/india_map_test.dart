import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

void main() {
  test("the india overlay is a country outline plus a rail network", () {
    final outline = jsonDecode(File("assets/india_outline.geojson").readAsStringSync()) as Map<String, dynamic>;
    final rail = jsonDecode(File("assets/india_rail.geojson").readAsStringSync()) as Map<String, dynamic>;
    final outlineGeometry = (outline["features"] as List).single["geometry"] as Map<String, dynamic>;
    final railGeometry = (rail["features"] as List).single["geometry"] as Map<String, dynamic>;
    final coasts = outlineGeometry["coordinates"] as List;
    final lines = railGeometry["coordinates"] as List;

    expect(outlineGeometry["type"], "MultiLineString");
    expect(coasts.length, greaterThan(1));
    expect(railGeometry["type"], "MultiLineString");
    expect(lines, isNotEmpty);
  });
}
