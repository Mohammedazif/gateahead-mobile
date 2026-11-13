import "dart:async";

import "package:flutter/material.dart";

import "../format.dart";
import "../models.dart";
import "../rail_controller.dart";
import "../theme.dart";
import "city_search.dart";

class TrainSheet extends StatelessWidget {
  const TrainSheet({
    super.key,
    required this.rail,
    required this.onLocate,
    required this.scroll,
    this.docked = false,
  });

  final RailController rail;
  final VoidCallback onLocate;
  final ScrollController scroll;
  final bool docked;

  @override
  Widget build(BuildContext context) {
    final place = rail.place;
    final gates = markGates(rail.gates, rail.predict);
    final shown = shownGates(gates);
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    final sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.sheet,
        borderRadius: docked
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(
          top: docked ? BorderSide.none : BorderSide(color: colors.line),
          left: docked ? BorderSide(color: colors.line) : BorderSide.none,
        ),
      ),
      child: ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          docked ? 22 : 18,
          docked ? 28 : 10,
          docked ? 22 : 18,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (!docked)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Image.asset(
                      "assets/branding/gateahead-mark-${colors.mode == RailThemeMode.light ? 'light' : 'dark'}.png",
                      width: 40,
                      height: 48,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("CROSSINGS", style: railEyebrow(colors)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "GateAhead",
                              style: text.titleLarge?.copyWith(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.2,
                                height: 1.05,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: RailThemeScope.of(context).onToggle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.ink,
                  side: BorderSide(color: colors.line),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(colors.toggleLabel),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _lede(rail),
            style: text.bodyLarge?.copyWith(color: colors.muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          CitySearch(
            api: rail.api,
            onPick: (city) => rail.openCity(
              "${city.name}, ${city.state}",
              city.lat,
              city.lon,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: rail.locating ? null : onLocate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.ink,
                  side: BorderSide(color: colors.line),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: Text(rail.locating ? "Finding…" : "Use my location"),
              ),
              FilledButton(
                onPressed: place == null || rail.checking
                    ? null
                    : () => rail.check(),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.amber,
                  foregroundColor: RailColors.inkDark,
                  disabledBackgroundColor: colors.amber.withValues(alpha: 0.45),
                  disabledForegroundColor: RailColors.inkDark.withValues(
                    alpha: 0.7,
                  ),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: Text(rail.checking ? "Checking…" : "Check trains"),
              ),
            ],
          ),
          if (rail.checkedAt != null) CheckedAgo(at: rail.checkedAt!),
          if (rail.error != null) ...[
            const SizedBox(height: 12),
            Text(
              rail.error!,
              style: text.bodyMedium?.copyWith(color: colors.warn),
            ),
          ],
          if (rail.gatesNote != null) ...[
            const SizedBox(height: 12),
            Text(
              rail.gatesNote!,
              style: text.bodyMedium?.copyWith(color: colors.warn),
            ),
          ],
          if (rail.predict != null) PredictBody(predict: rail.predict!),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text("ON THE MAP", style: railEyebrow(colors)),
            const SizedBox(height: 8),
            for (final gate in shown) ...[
              _GateRow(
                gate: gate,
                selected: gate.id == rail.selected?.id,
                onTap: () {
                  rail.openGate(gate);
                },
              ),
              const SizedBox(height: 8),
            ],
            if (gates.length > shown.length)
              Text(
                "The rest are marked on the map.",
                style: text.bodyMedium?.copyWith(color: colors.muted),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            "Tap a crossing to see the rail and the nearest train. Nothing is sent unless you ask.",
            style: text.bodyMedium?.copyWith(color: colors.muted, height: 1.4),
          ),
        ],
      ),
    );
    if (!docked) return sheet;
    return SizedBox.expand(child: sheet);
  }

  static String _lede(RailController rail) {
    final where = rail.placeLabel;
    if (rail.place == null) {
      return "Highlighted lines are the railway. Search an Indian city, tap the map, or share your location.";
    }
    if (rail.loadingGates) {
      return where == null
          ? "Looking up crossings…"
          : "Looking up crossings in $where…";
    }
    final prefix = where == null ? "" : "$where · ";
    if (rail.gatesNote != null) {
      return "${prefix}Crossings for this place did not load.";
    }
    if (rail.gates.isEmpty) {
      return "${prefix}No railway crossings on the map here.";
    }
    final count = rail.gates.length;
    return "$prefix$count ${count == 1 ? "crossing" : "crossings"} on this map.";
  }
}

class PredictBody extends StatelessWidget {
  const PredictBody({super.key, required this.predict});

  final Predict predict;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    if (predict.error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          friendlyError(predict.error),
          style: text.bodyMedium?.copyWith(color: colors.warn),
        ),
      );
    }
    final grouped = groupApproaches(predict.approaching);
    final sightings = lineSightings(predict);
    if (grouped.isEmpty && sightings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          "No live trains reported on this stretch right now.",
          style: text.bodyMedium?.copyWith(color: colors.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (grouped.isEmpty)
          Text(
            "No train is close enough to close a crossing near you right now.",
            style: text.bodyMedium?.copyWith(color: colors.muted),
          )
        else
          for (final entry in grouped.entries)
            _TrainBlock(number: entry.key, rows: entry.value),
        if (sightings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text("ON THIS LINE", style: railEyebrow(colors)),
          for (final row in sightings) _SightingBlock(row: row),
        ],
      ],
    );
  }
}

class _TrainBlock extends StatelessWidget {
  const _TrainBlock({required this.number, required this.rows});

  final String number;
  final List<Approach> rows;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final head = rows.first;
    final text = Theme.of(context).textTheme;
    final copy = runCopy(head.runInfo, showDelay: true);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      "$number ${head.name}",
                      style: text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPip(
                    status: head.status,
                    label: labelStatus(head.status),
                  ),
                ],
              ),
              RunLines(copy: copy),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.cluster.isEmpty ? "Level crossing" : row.cluster,
                        ),
                      ),
                      Text(
                        etaLabel(row.eta),
                        style: text.bodyMedium?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
              if (head.bracket.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    head.bracket,
                    style: text.bodyMedium?.copyWith(color: colors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SightingBlock extends StatelessWidget {
  const _SightingBlock({required this.row});

  final Sighting row;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    final copy = runCopy(row.runInfo);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  "${row.number} ${row.name}",
                  style: text.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              StatusPip(
                status: delayClass(row.runInfo.delay),
                label: delayLabel(row.runInfo.delay),
              ),
            ],
          ),
          RunLines(copy: copy),
          if (row.age >= 8)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Reported ${row.age.round()} min ago",
                style: text.bodyMedium?.copyWith(color: colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class RunLines extends StatelessWidget {
  const RunLines({super.key, required this.copy});

  final RunCopy copy;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    final quiet = style?.copyWith(color: colors.muted);
    final lines = <(String, TextStyle?)>[
      if (copy.route != null) (copy.route!, style),
      if (copy.place != null) (copy.place!, style),
      if (copy.scheduled != null) (copy.scheduled!, quiet),
      if (copy.delay != null) (copy.delay!, quiet),
      if (copy.next != null) (copy.next!, style),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(line.$1, style: line.$2),
          ),
      ],
    );
  }
}

class StatusPip extends StatelessWidget {
  const StatusPip({super.key, required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final filled =
        status == "closed" ||
        status == "closing_soon" ||
        status == "late" ||
        status == "early";
    final background = switch (status) {
      "closed" => colors.red,
      "closing_soon" || "late" || "early" => RailColors.closing,
      _ => Colors.transparent,
    };
    final foreground = status == "closed"
        ? Colors.white
        : (filled ? RailColors.inkDark : colors.amber);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: filled ? null : Border.all(color: colors.amber),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, letterSpacing: 0.4),
      ),
    );
  }
}

class _GateRow extends StatelessWidget {
  const _GateRow({
    required this.gate,
    required this.selected,
    required this.onTap,
  });

  final Gate gate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final hot = gate.eta != null;
    final border = selected
        ? colors.amber
        : hot
        ? RailColors.closing.withValues(alpha: 0.85)
        : colors.line;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  gate.name.isEmpty ? "Level crossing" : gate.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                gate.eta != null
                    ? etaLabel(gate.eta!)
                    : "${gate.km.toStringAsFixed(1)} km",
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: hot ? colors.hot : colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CheckedAgo extends StatefulWidget {
  const CheckedAgo({super.key, required this.at});

  final DateTime at;

  @override
  State<CheckedAgo> createState() => _CheckedAgoState();
}

class _CheckedAgoState extends State<CheckedAgo> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        checkedAgo(widget.at, DateTime.now()),
        style: text.bodyMedium?.copyWith(color: colors.muted, height: 1.45),
      ),
    );
  }
}
