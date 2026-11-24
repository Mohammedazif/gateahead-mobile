import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "api.dart";
import "device_store.dart";
import "phone_push.dart";
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
  final phonePush = await FirebasePhonePush.setup();
  final rail = RailController(
    HttpRailApi(base: defaultApiBase, storage: storage),
    storage: storage,
    phonePush: phonePush,
  );
  runApp(GateAheadApp(rail: rail, initialMode: mode, phonePush: phonePush));
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
    this.phonePush,
  });

  final RailController rail;
  final RailThemeMode initialMode;
  final FirebasePhonePush? phonePush;

  @override
  State<GateAheadApp> createState() => _GateAheadAppState();
}

class _GateAheadAppState extends State<GateAheadApp> {
  late RailThemeMode _mode = widget.initialMode;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _opened;
  StreamSubscription<CrossingNotification>? _foreground;

  @override
  void initState() {
    super.initState();
    final push = widget.phonePush;
    if (push == null) return;
    _opened = push.opened.listen(_openCrossing);
    _foreground = push.foreground.listen(_showNotification);
    unawaited(_openInitial(push));
  }

  Future<void> _openInitial(FirebasePhonePush push) async {
    final link = await push.initialLink();
    if (mounted && link != null) _openCrossing(link);
  }

  void _openCrossing(String link) {
    unawaited(widget.rail.openLink(link));
  }

  void _showNotification(CrossingNotification notice) {
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text("${notice.title}\n${notice.body}"),
        action: SnackBarAction(
          label: "View crossing",
          onPressed: () => _openCrossing(notice.link),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_opened?.cancel());
    unawaited(_foreground?.cancel());
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
        scaffoldMessengerKey: _messenger,
        home: HomePage(rail: widget.rail),
      ),
    );
  }
}
