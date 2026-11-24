import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:url_launcher/url_launcher.dart";

import "../api.dart";
import "../models.dart";
import "../theme.dart";

class CrossingAccessDetails extends StatefulWidget {
  const CrossingAccessDetails({
    super.key,
    required this.access,
    required this.gate,
    required this.api,
    this.saved = false,
  });

  final CrossingAccess access;
  final Gate gate;
  final RailApi api;
  final bool saved;

  @override
  State<CrossingAccessDetails> createState() => _CrossingAccessDetailsState();
}

class _CrossingAccessDetailsState extends State<CrossingAccessDetails> {
  bool _sending = false;
  bool _sent = false;
  String? _flagError;

  Future<void> _flag(CrossingDetailsApi api) async {
    setState(() {
      _sending = true;
      _flagError = null;
    });
    try {
      await api.flagCrossingDetails(widget.gate);
      if (mounted) setState(() => _sent = true);
    } on RailException catch (error) {
      if (mounted) setState(() => _flagError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _flagError = "Could not send your report. Try again.");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openBypass(CrossingBypass bypass) async {
    final point = "${bypass.place.lat},${bypass.place.lon}";
    final native = kIsWeb
        ? null
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => Uri.parse("geo:0,0?q=$point"),
            TargetPlatform.iOS => Uri.https("maps.apple.com", "/", {
              "ll": point,
              "q": point,
            }),
            _ => null,
          };
    final fallback = Uri.https("www.google.com", "/maps/search/", {
      "api": "1",
      "query": point,
    });
    for (final uri in [?native, fallback]) {
      try {
        final mode = uri.host == "maps.apple.com"
            ? LaunchMode.externalNonBrowserApplication
            : LaunchMode.externalApplication;
        if (await launchUrl(uri, mode: mode)) return;
      } catch (_) {
        // Try the web map if there is no matching native maps app.
      }
    }
    _message("Could not open a maps app for this bypass.");
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _accessLabel(RoadAccess access) => switch (access) {
    RoadAccess.allowed => "Allowed",
    RoadAccess.restricted => "Restricted",
    RoadAccess.unknown => "Unknown",
  };

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    final access = widget.access;
    final api = widget.api;
    return Theme(
      data: railActionTheme(context),
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(18),
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Crossing access", style: text.titleMedium),
            const SizedBox(height: 6),
            Text(switch (access.source) {
              "verified" => "Verified ${access.verifiedOn}",
              "mapped" => "From mapped road access",
              _ => "No road access evidence available",
            }, style: text.bodySmall?.copyWith(color: colors.muted)),
            if (widget.saved)
              Text(
                "Saved map details",
                style: text.bodySmall?.copyWith(color: colors.muted),
              ),
            const SizedBox(height: 10),
            for (final row in [
              ("Cars", access.cars),
              ("Two-wheelers", access.twoWheelers),
              ("Pedestrians", access.pedestrians),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(row.$1, style: text.bodyMedium)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _accessLabel(row.$2),
                        textAlign: TextAlign.end,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            if (access.bypasses.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text("Verified alternatives", style: text.titleSmall),
              for (final bypass in access.bypasses) ...[
                const SizedBox(height: 6),
                Text(
                  "${bypass.name}${bypass.replacement ? ' · replacement crossing' : ''} · verified ${bypass.verifiedOn}",
                  style: text.bodySmall?.copyWith(color: colors.muted),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openBypass(bypass),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    bypass.kind == "flyover"
                        ? "Open flyover in Maps"
                        : "Open underpass in Maps",
                  ),
                ),
              ],
            ],
            if (api is CrossingDetailsApi)
              TextButton.icon(
                onPressed: _sending || _sent
                    ? null
                    : () => _flag(api as CrossingDetailsApi),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text("Flag outdated details"),
              ),
            Semantics(
              liveRegion: true,
              child: switch ((_sending, _sent, _flagError)) {
                (true, _, _) => const Text("Sending flag…"),
                (_, true, _) => const Text("Outdated details flag sent."),
                (_, _, final String error) => Text(
                  error,
                  style: text.bodySmall?.copyWith(color: colors.warn),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
