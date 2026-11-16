import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:geolocator/geolocator.dart";
import "package:maplibre/maplibre.dart";

import "../format.dart";
import "../geo.dart";
import "../models.dart";
import "../rail_controller.dart";
import "../theme.dart";
import "train_sheet.dart";
import "location_control.dart";

const _indiaBounds = GeoBox(west: 68.17, south: 6.75, east: 97.34, north: 35.5);
const _wideLayout = 900.0;
const _indiaZoomFloor = 4.15;

const _networkRailWidth = Expression<num>.raw([
  "interpolate",
  ["linear"],
  ["zoom"],
  3,
  1.6,
  5,
  2.4,
  8,
  3.4,
]);

const _networkGlowWidth = Expression<num>.raw([
  "interpolate",
  ["linear"],
  ["zoom"],
  3,
  5,
  6,
  8,
  9,
  12,
]);

const _osmRailWidth = Expression<num>.raw([
  "interpolate",
  ["linear"],
  ["zoom"],
  7,
  1.8,
  12,
  3.2,
  16,
  5,
]);

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.rail});

  final RailController rail;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _visible = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
  }

  final GlobalKey _mapKey = GlobalKey();
  final ScrollController _dockScroll = ScrollController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  MapController? _map;
  Spot? _framedPlace;
  String? _framedRail;
  bool? _framedWide;
  int _indiaFrameTries = 0;
  int _styleTicket = 0;
  String? _outlineJson;
  String? _railJson;

  RailController get rail => widget.rail;

  @override
  void initState() {
    super.initState();
    rail.addListener(_onRail);
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => rail.autoCheck(visible: _visible),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    rail.removeListener(_onRail);
    _dockScroll.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  bool _isWide(Size size) =>
      size.width >= _wideLayout || (size.width >= 700 && size.height < 500);

  EdgeInsets _indiaPadding(bool wide, Size size) {
    if (wide) return const EdgeInsets.fromLTRB(56, 72, 40, 40);
    return EdgeInsets.fromLTRB(28, 56, 28, size.height * 0.42);
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
    _framedWide = null;
    _frameMap();
    _scheduleIndiaFrame();
  }

  void _scheduleIndiaFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _map == null || rail.place != null) return;
      final wide = _isWide(MediaQuery.sizeOf(context));
      final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || box.size.shortestSide < 64) {
        if (_indiaFrameTries++ < 30) {
          _scheduleIndiaFrame();
        }
        return;
      }
      if (_framedWide == wide) return;
      _framedWide = wide;
      _indiaFrameTries = 0;
      unawaited(_openOnIndia(_map!, wide));
    });
  }

  Future<void> _openOnIndia(MapController map, bool wide) async {
    final fitted = await map.cameraFor(
      CameraUpdate.bounds(
        _indiaBounds,
        padding: _indiaPadding(wide, MediaQuery.sizeOf(context)),
      ),
    );
    if (!mounted || _map != map || rail.place != null) return;
    final zoom = fitted.zoom < _indiaZoomFloor ? _indiaZoomFloor : fitted.zoom;
    await map.moveCamera(
      CameraUpdate.position(center: fitted.center, zoom: zoom),
    );
  }

  void _onMapClick(MapEventClick event) {
    rail.askPlace(event.point.lat, event.point.lon);
  }

  void _onStyleLoaded(StyleController style) {
    final ticket = ++_styleTicket;
    unawaited(_paintIndia(style, ticket));
  }

  Future<void> _paintIndia(StyleController style, int ticket) async {
    try {
      final outline = _outlineJson ??= await rootBundle.loadString(
        "assets/india_outline.geojson",
      );
      final network = _railJson ??= await rootBundle.loadString(
        "assets/india_rail.geojson",
      );
      if (!mounted || ticket != _styleTicket) return;
      final colors = RailColors.of(context);
      final light = colors.mode == RailThemeMode.light;
      final Expression<Color> railColor = .literal(colors.rail);
      final Expression<Color> outlineColor = .literal(
        light ? const Color(0xFF8A4E0D) : const Color(0xFFE7C89A),
      );
      for (final layer in style.layers.toList()) {
        if (!layer.id.startsWith("railway")) continue;
        if (layer.id.contains("dash")) {
          layer.visible = false;
          continue;
        }
        if (layer is LineStyleLayer) {
          layer
            ..minZoom = 7
            ..color = railColor
            ..width = _osmRailWidth
            ..cap = const .literal(LineCap.round)
            ..join = const .literal(LineJoin.round);
        }
      }
      if (style.sources["india-outline"] == null) {
        await style.sources.add(
          GeoJsonSource.data(
            id: "india-outline",
            data: GeoJsonData.text(outline),
          ),
        );
      }
      if (!mounted || ticket != _styleTicket) return;
      if (style.layers["india-outline"] == null) {
        await style.layers.add(
          LineStyleLayer(
            id: "india-outline",
            sourceId: "india-outline",
            maxZoom: 9,
            color: outlineColor,
            width: const .literal(1.25),
            opacity: .literal(light ? 0.55 : 0.72),
          ),
        );
      }
      if (!mounted || ticket != _styleTicket) return;
      if (style.sources["india-rail"] == null) {
        await style.sources.add(
          GeoJsonSource.data(id: "india-rail", data: GeoJsonData.text(network)),
        );
      }
      if (!mounted || ticket != _styleTicket) return;
      if (style.layers["india-rail-glow"] == null) {
        await style.layers.add(
          LineStyleLayer(
            id: "india-rail-glow",
            sourceId: "india-rail",
            maxZoom: 10,
            color: railColor,
            width: _networkGlowWidth,
            opacity: .literal(light ? 0.22 : 0.42),
            blur: const .literal(1.2),
            cap: const .literal(LineCap.round),
            join: const .literal(LineJoin.round),
          ),
        );
      }
      if (!mounted || ticket != _styleTicket) return;
      if (style.layers["india-rail"] == null) {
        await style.layers.add(
          LineStyleLayer(
            id: "india-rail",
            sourceId: "india-rail",
            maxZoom: 10,
            color: railColor,
            width: _networkRailWidth,
            cap: const .literal(LineCap.round),
            join: const .literal(LineJoin.round),
          ),
        );
      }
    } catch (_) {
      if (!mounted || ticket != _styleTicket) return;
      rethrow;
    }
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
    if (scene != null &&
        scene.available &&
        scene.rail.length >= 2 &&
        selected != null &&
        selected != _framedRail) {
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
          animation: const CameraAnimation.ease(
            duration: Duration(milliseconds: 400),
          ),
        ),
      );
      return;
    }
    if (placeChanged) {
      unawaited(
        map.moveCamera(
          CameraUpdate.position(
            center: Geographic(lon: place.lon, lat: place.lat),
            zoom: 14,
          ),
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
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
    final gates = markGates(rail.gates, rail.historical ? null : rail.predict);
    final scene = rail.scene;
    final lead =
        !rail.sceneHistorical && scene != null && scene.trains.isNotEmpty
        ? scene.trains.first
        : null;
    final railLine = scene?.rail ?? const <Spot>[];
    final trainSpot =
        lead != null &&
            lead.positionOnSegment &&
            lead.ageMin < 8 &&
            railLine.length >= 2
        ? pointAlongKm(railLine, lead.alongKm)
        : null;
    final size = MediaQuery.sizeOf(context);
    final wide = _isWide(size);
    if (_map != null && rail.place == null && _framedWide != wide) {
      _scheduleIndiaFrame();
    }
    final map = Stack(
      fit: StackFit.expand,
      children: [
        MapLibreMap(
          key: _mapKey,
          options: MapOptions(
            style: MapStyle.url(colors.mapStyle),
            minZoom: 3.2,
            initCamera: CameraUpdate.bounds(
              _indiaBounds,
              padding: _indiaPadding(wide, size),
            ),
          ),
          onMapCreated: _onMapCreated,
          onStyleLoaded: _onStyleLoaded,
          onClick: _onMapClick,
          layers: [
            if (scene != null && scene.rail.length >= 2)
              PolylineLayer(
                polylines: [
                  Feature(
                    geometry: LineString.from([
                      for (final point in scene.rail)
                        Geographic(lon: point.lon, lat: point.lat),
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
                    point: Geographic(
                      lon: rail.place!.lon,
                      lat: rail.place!.lat,
                    ),
                    size: const Size.square(18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.markerInk,
                        border: const Border.fromBorderSide(
                          BorderSide(color: RailColors.mapRed, width: 2),
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                if (rail.pending != null)
                  Marker(
                    point: Geographic(
                      lon: rail.pending!.lon,
                      lat: rail.pending!.lat,
                    ),
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
                      decoration: BoxDecoration(
                        color: colors.rail,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.train,
                        color: RailColors.inkDark,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 14,
          left: 14,
          right: 76,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: LocationControl(rail: rail, onLocate: _locate),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: map),
                SizedBox(
                  width: 400,
                  child: TrainSheet(
                    rail: rail,
                    onLocate: _locate,
                    scroll: _dockScroll,
                    docked: true,
                  ),
                ),
              ],
            )
          else ...[
            map,
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: (150 / size.height).clamp(.42, .5).toDouble(),
              minChildSize: (150 / size.height).clamp(.28, .5).toDouble(),
              maxChildSize: 0.86,
              builder: (context, scroll) => TrainSheet(
                rail: rail,
                onLocate: _locate,
                scroll: scroll,
                onExpand: () {
                  if (_sheetController.isAttached) {
                    _sheetController.animateTo(
                      _sheetController.size > .65
                          ? (150 / size.height).clamp(.42, .5).toDouble()
                          : .82,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                onResize: (delta) {
                  if (_sheetController.isAttached) {
                    _sheetController.jumpTo(
                      (_sheetController.size - delta / size.height)
                          .clamp((150 / size.height).clamp(.28, .5), .86)
                          .toDouble(),
                    );
                  }
                },
              ),
            ),
          ],
          if (rail.pending != null) _ConfirmCard(rail: rail),
        ],
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.rail});

  final RailController rail;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final pending = rail.pending!;
    final title =
        rail.spotName ??
        (rail.naming
            ? "Finding this place…"
            : formatSpot(pending.lat, pending.lon));
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: rail.cancelPending,
            child: ColoredBox(color: colors.veil),
          ),
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
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Look up crossings at this point?",
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: colors.muted),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: rail.cancelPending,
                              child: const Text("Cancel"),
                            ),
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
