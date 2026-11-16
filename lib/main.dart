import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "api.dart";
import "device_store.dart";

import "package:shared_preferences/shared_preferences.dart";

import "dart:async";

import "rail_controller.dart";
import "theme.dart";
import "ui/home_page.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mode = await RailThemeStore.read();
  _overlay(RailColors.forMode(mode));
  final storage = DeviceStore(
    await SharedPreferences.getInstance(),
    namespace: defaultApiBase,
  );
  final rail = RailController(
    HttpRailApi(base: defaultApiBase, storage: storage),
    storage: storage,
  );
  runApp(GateAheadApp(rail: rail, initialMode: mode));
  unawaited(rail.restore());
}

void _overlay(RailColors colors) {
  final lightMode = colors.mode == RailThemeMode.light;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: lightMode ? Brightness.dark : Brightness.light,
      statusBarBrightness: lightMode ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: colors.bg,
      systemNavigationBarIconBrightness: lightMode
          ? Brightness.dark
          : Brightness.light,
    ),
  );
}

class GateAheadApp extends StatefulWidget {
  const GateAheadApp({
    super.key,
    required this.rail,
    this.initialMode = RailThemeMode.dark,
  });

  final RailController rail;
  final RailThemeMode initialMode;

  @override
  State<GateAheadApp> createState() => _GateAheadAppState();
}

class _GateAheadAppState extends State<GateAheadApp> {
  late RailThemeMode _mode = widget.initialMode;

  @override
  void dispose() {
    widget.rail.dispose();
    super.dispose();
  }

  Future<void> _toggleTheme() async {
    final next = _mode == RailThemeMode.light
        ? RailThemeMode.dark
        : RailThemeMode.light;
    setState(() => _mode = next);
    _overlay(RailColors.forMode(next));
    await RailThemeStore.write(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.forMode(_mode);
    return RailThemeScope(
      onToggle: _toggleTheme,
      child: MaterialApp(
        title: "GateAhead",
        debugShowCheckedModeBanner: false,
        theme: railTheme(colors),
        themeAnimationDuration: Duration.zero,
        home: HomePage(rail: widget.rail),
      ),
    );
  }
}
