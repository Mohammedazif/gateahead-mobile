import "dart:math" as math;

import "models.dart";

double kmBetween(Spot a, Spot b) {
  const scaleY = 110.57;
  final scaleX = 111.32 * math.max(0.2, math.cos(a.lat * math.pi / 180).abs());
  final dx = (b.lon - a.lon) * scaleX;
  final dy = (b.lat - a.lat) * scaleY;
  return math.sqrt(dx * dx + dy * dy);
}

Spot pointAlongKm(List<Spot> line, double alongKm) {
  if (line.isEmpty) {
    throw ArgumentError("rail line is empty");
  }
  if (line.length == 1 || alongKm <= 0) return line.first;
  var walked = 0.0;
  for (var i = 0; i < line.length - 1; i++) {
    final start = line[i];
    final end = line[i + 1];
    final span = kmBetween(start, end);
    final remaining = alongKm - walked;
    final last = i == line.length - 2;
    if (span >= remaining || last) {
      final t = span < 1e-9 ? 0.0 : (remaining / span).clamp(0.0, 1.0);
      return Spot(
        start.lat + (end.lat - start.lat) * t,
        start.lon + (end.lon - start.lon) * t,
      );
    }
    walked += span;
  }
  return line.last;
}
