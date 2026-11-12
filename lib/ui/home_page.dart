import "dart:async";

import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:maplibre/maplibre.dart";

import "../format.dart";
import "../geo.dart";
import "../models.dart";
import "../rail_controller.dart";
import "../theme.dart";
import "train_sheet.dart";

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.rail});

  final RailController rail;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapController? _map;
  Spot? _framedPlace;
  String? _framedRail;

  RailController get rail => widget.rail;

  @override
  void initState() {
    super.initState();
    rail.addListener(_onRail);
  }

  @override
  void dispose() {
    rail.removeListener(_onRail);
    super.dispose();
  }

  void _onRail() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _frameMap();
    });
  }

  void _onMapCreated(MapController controller) {
    _map = controller;
    _framedPlace = null;
    _framedRail = null;
    _frameMap();
  }

  void _onMapClick(MapEventClick event) {
    rail.askPlace(event.point.lat, event.point.lon);
  }

  void _frameMap() {
    final map = _map;
    if (map == null) return;
    final place = rail.place;
    final placeChanged = place != null && place != _framedPlace;
    if (placeChanged) {
      _framedPlace = place;
      _framedRail = null;
    }
    final scene = rail.scene;
    final selected = rail.selected?.id;
    if (scene != null && scene.available && scene.rail.length >= 2 && selected != null && selected != _framedRail) {
      _framedRail = selected;
      var west = scene.rail.first.lon;
      var east = west;
      var south = scene.rail.first.lat;
      var north = south;
      for (final point in scene.rail) {
        west = west < point.lon ? west : point.lon;
        east = east > point.lon ? east : point.lon;
        south = south < point.lat ? south : point.lat;
        north = north > point.lat ? north : point.lat;
      }
      if ((east - west).abs() < 0.002) {
        west -= 0.002;
        east += 0.002;
      }
      if ((north - south).abs() < 0.002) {
        south -= 0.002;
        north += 0.002;
      }
      unawaited(
        map.animateCamera(
          CameraUpdate.bounds(
            GeoBox(west: west, south: south, east: east, north: north),
            padding: const EdgeInsets.fromLTRB(48, 96, 48, 200),
          ),
          animation: const CameraAnimation.ease(duration: Duration(milliseconds: 400)),
        ),
      );
      return;
    }
    if (placeChanged) {
      unawaited(
        map.moveCamera(
          CameraUpdate.position(center: Geographic(lon: place.lon, lat: place.lat), zoom: 14),
        ),
      );
    }
  }

  Future<void> _locate() async {
    rail.beginLocate();
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        rail.failLocation();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        rail.failLocation();
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await rail.choosePlace(position.latitude, position.longitude);
    } catch (_) {
      rail.failLocation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final gates = markGates(rail.gates, rail.predict);
    final scene = rail.scene;
    final lead = scene != null && scene.trains.isNotEmpty ? scene.trains.first : null;
    final railLine = scene?.rail ?? const <Spot>[];
    final trainSpot = lead != null && railLine.length >= 2 ? pointAlongKm(railLine, lead.alongKm) : null;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          MapLibreMap(
            options: MapOptions(
              style: MapStyle.url(colors.mapStyle),
              initCamera: const CameraUpdate.position(center: Geographic(lon: 78.96, lat: 20.59), zoom: 4.2),
            ),
            onMapCreated: _onMapCreated,
            onClick: _onMapClick,
            layers: [
              if (scene != null && scene.rail.length >= 2)
                PolylineLayer(
                  polylines: [
                    Feature(
                      geometry: LineString.from([
                        for (final point in scene.rail) Geographic(lon: point.lon, lat: point.lat),
                      ]),
                    ),
                  ],
                  color: .literal(colors.rail),
                  width: const .literal(4),
                ),
            ],
            children: [
              WidgetLayer(
                allowInteraction: true,
                markers: [
                  for (final gate in gates)
                    Marker(
                      point: Geographic(lon: gate.lon, lat: gate.lat),
                      size: Size.square(gate.id == rail.selected?.id ? 28 : 22),
                      child: GestureDetector(
                        onTap: () => rail.openGate(gate),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gateColor(gate.status),
                            border: Border.all(
                              color: colors.markerInk,
                              width: gate.id == rail.selected?.id ? 3 : 1.5,
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  if (rail.place != null)
                    Marker(
                      point: Geographic(lon: rail.place!.lon, lat: rail.place!.lat),
                      size: const Size.square(18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.markerInk,
                          border: const Border.fromBorderSide(BorderSide(color: RailColors.mapRed, width: 2)),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  if (rail.pending != null)
                    Marker(
                      point: Geographic(lon: rail.pending!.lon, lat: rail.pending!.lat),
                      size: const Size.square(28),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.amber, width: 3),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  if (trainSpot != null)
                    Marker(
                      point: Geographic(lon: trainSpot.lon, lat: trainSpot.lat),
                      size: const Size.square(28),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: colors.rail, shape: BoxShape.circle),
                        child: const Icon(Icons.train, color: RailColors.inkDark, size: 18),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: Text(
              "OpenFreeMap © OpenMapTiles Data from OpenStreetMap",
              style: TextStyle(color: colors.muted, fontSize: 11),
            ),
          ),
          if (rail.selected != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 88,
              child: _RunCard(rail: rail),
            ),
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.22,
            maxChildSize: 0.86,
            builder: (context, scroll) => TrainSheet(rail: rail, onLocate: _locate, scroll: scroll),
          ),
          if (rail.pending != null) _ConfirmCard(rail: rail),
        ],
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.rail});

  final RailController rail;

  @override
  Widget build(BuildContext context) {
    final scene = rail.scene;
    final crossing = scene?.crossing;
    final name = crossing?.name.isNotEmpty == true
        ? crossing!.name
        : (rail.selected?.name.isNotEmpty == true ? rail.selected!.name : "Level crossing");
    final lead = scene != null && scene.trains.isNotEmpty ? scene.trains.first : null;
    final message = rail.sceneLoading ? "Opening the crossing…" : rail.sceneMessage;
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: colors.sheet,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ON THE MAP", style: railEyebrow(colors)),
                  Text(name, style: text.headlineMedium),
                  if (message != null)
                    Text(message, style: text.bodyMedium?.copyWith(color: colors.muted))
                  else if (lead != null) ...[
                    Text(_leadLine(lead), style: text.bodyMedium?.copyWith(color: colors.muted)),
                    Text(
                      "The gate closes the road. The train keeps the track.",
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                    ),
                  ] else if (scene != null)
                    Text(
                      "No train is close enough to close this crossing. The track stays in view.",
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
            TextButton(onPressed: rail.closeScene, child: const Text("Close")),
          ],
        ),
      ),
    );
  }

  String _leadLine(SceneTrain lead) {
    final when = lead.etaMin <= 1 ? "closing now" : "closes in ${lead.etaMin.round()} min";
    final age = lead.ageMin >= 8 ? " · last reported" : "";
    final bracket = lead.bracket.isEmpty ? "" : " · ${lead.bracket}";
    return "${lead.number} ${lead.name} · $when$age$bracket";
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.rail});

  final RailController rail;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final pending = rail.pending!;
    final title = rail.spotName ?? (rail.naming ? "Finding this place…" : formatSpot(pending.lat, pending.lon));
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(onTap: rail.cancelPending, child: ColoredBox(color: colors.veil)),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: colors.sheet,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("YOU TAPPED", style: railEyebrow(colors)),
                        const SizedBox(height: 4),
                        Text(title, style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text(
                          "Look up crossings at this point?",
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.muted),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: rail.cancelPending, child: const Text("Cancel")),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => rail.confirmPlace(),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.amber,
                                foregroundColor: RailColors.inkDark,
                                shape: const StadiumBorder(),
                              ),
                              child: const Text("Look up"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _gateColor(String? status) {
  switch (status) {
    case "closed":
      return RailColors.mapRed;
    case "closing_soon":
      return RailColors.closing;
    default:
      return RailColors.dark.amber;
  }
}
