import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:shared_preferences/shared_preferences.dart";

enum RailThemeMode { dark, light }

class RailColors extends ThemeExtension<RailColors> {
  const RailColors({
    required this.mode,
    required this.bg,
    required this.sheet,
    required this.ink,
    required this.muted,
    required this.amber,
    required this.accent,
    required this.red,
    required this.warn,
    required this.hot,
    required this.line,
    required this.veil,
    required this.markerInk,
    required this.rail,
    required this.mapStyle,
  });

  final RailThemeMode mode;
  final Color bg;
  final Color sheet;
  final Color ink;
  final Color muted;
  final Color amber;
  final Color accent;
  final Color red;
  final Color warn;
  final Color hot;
  final Color line;
  final Color veil;
  final Color markerInk;
  final Color rail;
  final String mapStyle;

  static const inkDark = Color(0xFF1A1208);
  static const mapRed = Color(0xFFC4382F);
  static const closing = Color(0xFFE07A2F);

  static const dark = RailColors(
    mode: RailThemeMode.dark,
    bg: Color(0xFF0E1214),
    sheet: Color(0xFF14181B),
    ink: Color(0xFFF4EFE6),
    muted: Color(0xFFB7AEA2),
    amber: Color(0xFFE7A23A),
    accent: Color(0xFFE7A23A),
    red: Color(0xFFC4382F),
    warn: Color(0xFFE7B2A4),
    hot: Color(0xFFF0C7A2),
    line: Color(0x24F4EFE6),
    veil: Color(0x6B06080A),
    markerInk: Color(0xFFF7F1E6),
    rail: Color(0xFFE7A23A),
    mapStyle: "https://tiles.openfreemap.org/styles/dark",
  );

  static const light = RailColors(
    mode: RailThemeMode.light,
    bg: Color(0xFFF3EEE6),
    sheet: Color(0xFFFFFAF3),
    ink: Color(0xFF1C1612),
    muted: Color(0xFF5C534B),
    amber: Color(0xFFE7A23A),
    accent: Color(0xFF8A4E0D),
    red: Color(0xFFB4332B),
    warn: Color(0xFF8D3328),
    hot: Color(0xFF8A4E0D),
    line: Color(0x291C1612),
    veil: Color(0x471C1612),
    markerInk: Color(0xFF241910),
    rail: Color(0xFFB86A12),
    mapStyle: "https://tiles.openfreemap.org/styles/positron",
  );

  String get toggleLabel => mode == RailThemeMode.light ? "Dark" : "Light";

  static RailColors forMode(RailThemeMode mode) => mode == RailThemeMode.light ? light : dark;

  static RailColors of(BuildContext context) => Theme.of(context).extension<RailColors>() ?? dark;

  @override
  RailColors copyWith({
    RailThemeMode? mode,
    Color? bg,
    Color? sheet,
    Color? ink,
    Color? muted,
    Color? amber,
    Color? accent,
    Color? red,
    Color? warn,
    Color? hot,
    Color? line,
    Color? veil,
    Color? markerInk,
    Color? rail,
    String? mapStyle,
  }) {
    return RailColors(
      mode: mode ?? this.mode,
      bg: bg ?? this.bg,
      sheet: sheet ?? this.sheet,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      amber: amber ?? this.amber,
      accent: accent ?? this.accent,
      red: red ?? this.red,
      warn: warn ?? this.warn,
      hot: hot ?? this.hot,
      line: line ?? this.line,
      veil: veil ?? this.veil,
      markerInk: markerInk ?? this.markerInk,
      rail: rail ?? this.rail,
      mapStyle: mapStyle ?? this.mapStyle,
    );
  }

  @override
  RailColors lerp(ThemeExtension<RailColors>? other, double t) {
    if (other is! RailColors) return this;
    final next = t < 0.5 ? this : other;
    return RailColors(
      mode: next.mode,
      bg: Color.lerp(bg, other.bg, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      red: Color.lerp(red, other.red, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      hot: Color.lerp(hot, other.hot, t)!,
      line: Color.lerp(line, other.line, t)!,
      veil: Color.lerp(veil, other.veil, t)!,
      markerInk: Color.lerp(markerInk, other.markerInk, t)!,
      rail: Color.lerp(rail, other.rail, t)!,
      mapStyle: next.mapStyle,
    );
  }
}

TextStyle railEyebrow(RailColors colors) {
  return TextStyle(
    color: colors.accent,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.6,
  );
}

ThemeData railTheme(RailColors colors) {
  final lightMode = colors.mode == RailThemeMode.light;
  final base = ThemeData(
    brightness: lightMode ? Brightness.light : Brightness.dark,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: (lightMode ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
      surface: colors.sheet,
      primary: colors.amber,
      onPrimary: RailColors.inkDark,
      onSurface: colors.ink,
    ),
    extensions: [colors],
  );
  final outfit = GoogleFonts.outfitTextTheme(base.textTheme).apply(
    bodyColor: colors.ink,
    displayColor: colors.ink,
  );
  return base.copyWith(
    textTheme: outfit.copyWith(
      headlineLarge: GoogleFonts.fraunces(
        textStyle: outfit.headlineLarge,
        fontWeight: FontWeight.w600,
        fontSize: 40,
        height: 0.95,
        color: colors.ink,
      ),
      headlineMedium: GoogleFonts.fraunces(
        textStyle: outfit.headlineMedium,
        fontWeight: FontWeight.w600,
        fontSize: 26,
        height: 1.1,
        color: colors.ink,
      ),
    ),
    extensions: [colors],
  );
}

ThemeData railActionTheme(BuildContext context) {
  final theme = Theme.of(context);
  final accent = RailColors.of(context).accent;
  return theme.copyWith(
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).merge(
        TextButton.styleFrom(foregroundColor: accent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).merge(
        OutlinedButton.styleFrom(foregroundColor: accent),
      ),
    ),
  );
}

class RailThemeStore {
  static const key = "gateahead-theme";
  static const legacyKey = "smartrail-theme";

  static Future<RailThemeMode> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key) ?? prefs.getString(legacyKey);
      return saved == "light" ? RailThemeMode.light : RailThemeMode.dark;
    } catch (_) {
      return RailThemeMode.dark;
    }
  }

  static Future<void> write(RailThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, mode == RailThemeMode.light ? "light" : "dark");
      await prefs.remove(legacyKey);
    } catch (_) {
      // Storage can be blocked. The toggle still applies for this visit.
    }
  }
}

class RailThemeScope extends InheritedWidget {
  const RailThemeScope({super.key, required this.onToggle, required super.child});

  final VoidCallback onToggle;

  static RailThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RailThemeScope>();
    if (scope == null) throw StateError("RailThemeScope is missing");
    return scope;
  }

  @override
  bool updateShouldNotify(RailThemeScope oldWidget) => false;
}
