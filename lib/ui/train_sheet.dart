import "dart:async";

import "package:flutter/material.dart";

import "../format.dart";
import "../models.dart";
import "../rail_controller.dart";
import "../theme.dart";
import "feature_controls.dart";
import "location_control.dart";

enum _SheetTab { nearby, trains, saved }

class TrainSheet extends StatefulWidget {
  const TrainSheet({
    super.key,
    required this.rail,
    required this.onLocate,
    required this.scroll,
    this.docked = false,
    this.onExpand,
    this.onResize,
  });
  final RailController rail;
  final VoidCallback onLocate;
  final ScrollController scroll;
  final bool docked;
  final VoidCallback? onExpand;
  final ValueChanged<double>? onResize;
  @override
  State<TrainSheet> createState() => _TrainSheetState();
}

class _TrainSheetState extends State<TrainSheet> {
  _SheetTab _tab = _SheetTab.nearby;
  String? _gateId;
  Spot? _place;
  bool _showAllCrossings = false;
  RailController get rail => widget.rail;
  @override
  void initState() {
    super.initState();
    _gateId = rail.selected?.id;
    _place = rail.place;
    rail.addListener(_changed);
  }

  @override
  void didUpdateWidget(TrainSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rail != rail) {
      oldWidget.rail.removeListener(_changed);
      rail.addListener(_changed);
    }
  }

  @override
  void dispose() {
    rail.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final focusChanged = _gateId != rail.selected?.id || _place != rail.place;
    if (_place != rail.place) _showAllCrossings = false;
    if (_place != rail.place ||
        (_gateId != rail.selected?.id && rail.selected != null)) {
      _tab = _SheetTab.nearby;
    }
    _gateId = rail.selected?.id;
    _place = rail.place;
    setState(() {});
    if (focusChanged) _scrollToTop();
  }

  void _scrollToTop() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.scroll.hasClients) widget.scroll.jumpTo(0);
  });
  void _changeTab(_SheetTab tab) {
    rail.closeScene();
    setState(() => _tab = tab);
    _scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    final gates = rail.markedGates;
    final shown = shownCrossings(gates, showAll: _showAllCrossings);
    final crossingCount = physicalCrossings(gates).length;
    final horizontal = widget.docked ? 22.0 : 18.0;
    return DecoratedBox(
      key: const ValueKey("train-sheet-surface"),
      decoration: BoxDecoration(
        color: colors.sheet,
        borderRadius: widget.docked
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: widget.docked ? BorderSide.none : BorderSide(color: colors.line),
          left: widget.docked
              ? BorderSide(color: colors.line)
              : BorderSide.none,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            if (!widget.docked)
              Semantics(
                label: "Expand or collapse panel",
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onExpand,
                  onVerticalDragUpdate: widget.onResize == null
                      ? null
                      : (details) => widget.onResize!(details.delta.dy),
                  child: SizedBox(
                    height: 22,
                    width: double.infinity,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.muted.withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                widget.docked ? 22 : 0,
                horizontal,
                8,
              ),
              child: Row(
                children: [
                  Image.asset(
                    "assets/branding/gateahead-mark-${colors.mode == RailThemeMode.light ? 'light' : 'dark'}.png",
                    width: 28,
                    height: 34,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      "GateAhead",
                      style: text.titleLarge?.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "Open settings",
                    onPressed: () => showRailSettings(context, rail),
                    icon: const Icon(Icons.tune, size: 21),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              child: Row(
                children: [
                  for (final tab in _SheetTab.values)
                    Expanded(
                      child: Semantics(
                        selected: _tab == tab,
                        child: TextButton(
                          onPressed: () => _changeTab(tab),
                          style: TextButton.styleFrom(
                            foregroundColor: _tab == tab
                                ? colors.accent
                                : colors.muted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 4,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  Icon(switch (tab) {
                                    _SheetTab.nearby =>
                                      Icons.location_on_outlined,
                                    _SheetTab.trains => Icons.train_outlined,
                                    _SheetTab.saved => Icons.bookmark_border,
                                  }, size: 18),
                                  Text(switch (tab) {
                                    _SheetTab.nearby => "Nearby",
                                    _SheetTab.trains => "Trains",
                                    _SheetTab.saved => "Saved",
                                  }, textAlign: TextAlign.center),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 2,
                                color: _tab == tab
                                    ? colors.amber
                                    : Colors.transparent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.line),
            Expanded(
              child: ListView(
                controller: widget.scroll,
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  20,
                  horizontal,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  if (rail.selected != null)
                    _CrossingDetails(
                      rail: rail,
                      onBack: () {
                        rail.closeScene();
                        setState(() => _tab = _SheetTab.nearby);
                      },
                    )
                  else ...[
                    if (_tab == _SheetTab.nearby) ...[
                      _PanelHeading(
                        title: "Nearby crossings",
                        action: rail.place == null
                            ? null
                            : TextButton(
                                onPressed: rail.checking
                                    ? null
                                    : () {
                                        setState(() => _tab = _SheetTab.trains);
                                        rail.check();
                                      },
                                child: Text(
                                  rail.checking ? "Checking…" : "Check trains",
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _lede(rail),
                        style: text.bodyMedium?.copyWith(
                          color: colors.muted,
                          height: 1.5,
                        ),
                      ),
                      if (rail.gatesCached)
                        const _Notice(
                          "Saved crossing locations · map tiles need a connection.",
                        ),
                      if (rail.gatesNote != null) ...[
                        _Notice(rail.gatesNote!),
                        TextButton.icon(
                          onPressed: rail.loadingGates ? null : rail.retryGates,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text("Retry crossing lookup"),
                        ),
                      ],
                      if (rail.place == null)
                        _EmptyState(
                          icon: Icons.location_on_outlined,
                          title: "Start with a place",
                          message:
                              "Find your city or choose a point on the map.",
                          action: TextButton(
                            onPressed: () => showLocationSearch(
                              context,
                              rail,
                              widget.onLocate,
                            ),
                            child: const Text("Choose a place"),
                          ),
                        ),
                      if (shown.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        for (final crossing in shown) ...[
                          if (crossing.members.length == 1)
                            _GateRow(
                              gate: crossing.first,
                              selected: crossing.first.id == rail.selected?.id,
                              onTap: () => rail.openGate(crossing.first),
                            )
                          else
                            _GateGroupRow(
                              key: ValueKey("physical:${crossing.key}"),
                              crossing: crossing,
                              rail: rail,
                            ),
                          const SizedBox(height: 10),
                        ],
                        if (crossingCount > shown.length)
                          TextButton(
                            onPressed: () =>
                                setState(() => _showAllCrossings = true),
                            child: Text("Show all $crossingCount crossings"),
                          ),
                      ],
                    ],
                    if (_tab == _SheetTab.trains) ...[
                      _PanelHeading(
                        title: "On this stretch",
                        action: FilledButton(
                          onPressed: rail.place == null || rail.checking
                              ? null
                              : () => rail.check(),
                          child: Text(
                            rail.checking ? "Checking…" : "Check trains",
                          ),
                        ),
                      ),
                      if (rail.checkedAt != null && !rail.historical)
                        CheckedAgo(at: rail.checkedAt!),
                      if (rail.historical)
                        _Notice(
                          "Saved check · ${rail.checkedAt?.toLocal()}. Timings may have changed.",
                        ),
                      if (rail.predict != null)
                        PredictBody(predict: rail.predict!, gates: gates)
                      else
                        _EmptyState(
                          icon: Icons.train_outlined,
                          title: rail.place == null
                              ? "Choose an area first"
                              : "See what’s on the line",
                          message: rail.place == null
                              ? "Use the search above the map to find your crossings."
                              : "Check trains for approaching services and estimated crossing times.",
                        ),
                    ],
                    if (_tab == _SheetTab.saved) ...[
                      const _PanelHeading(title: "Saved gates"),
                      const SizedBox(height: 8),
                      Text(
                        "A shortcut to the crossings you use most.",
                        style: text.bodyMedium?.copyWith(color: colors.muted),
                      ),
                      SavedGateControls(rail: rail),
                    ],
                    if (rail.error != null && _tab != _SheetTab.saved)
                      _Notice(rail.error!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _lede(RailController rail) {
    if (rail.place == null) {
      return "Search for an area to find nearby crossings.";
    }
    final prefix = rail.placeLabel == null ? "" : "${rail.placeLabel} · ";
    if (rail.loadingGates) return "${prefix}Looking up crossings…";
    if (rail.gatesNote != null && rail.gates.isEmpty) {
      return "${prefix}Crossings for this place did not load.";
    }
    final count = physicalCrossings(rail.gates).length;
    if (count == 0) return "${prefix}No railway crossings on the map here.";
    return "$prefix$count ${count == 1 ? 'crossing' : 'crossings'} on this map.";
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontSize: 19, fontWeight: FontWeight.w600),
        ),
      ),
      if (action != null) ...[const SizedBox(width: 8), action!],
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: colors.accent),
          const SizedBox(height: 14),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: colors.muted, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.amber, width: 2)),
        color: colors.line.withValues(alpha: .05),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: colors.muted, height: 1.5),
      ),
    );
  }
}

class _AwaitingUpdates extends StatelessWidget {
  const _AwaitingUpdates(this.trains);
  final List<AwaitingTrain> trains;
  @override
  Widget build(BuildContext context) => trains.isEmpty
      ? const SizedBox.shrink()
      : _Notice(
          "Position update needed\n${trains.map(_lastReport).join('\n')}\nPassage has not been confirmed. The barrier’s position is unknown.",
        );

  static String _lastReport(AwaitingTrain train) {
    final who = "${train.number} ${train.name}";
    final place = train.current.isEmpty ? "" : " at ${train.current}";
    if (train.reason == "unknown_report_age") {
      return "$who · last reported$place, report age unknown";
    }
    final previous = train.reason == "stopped_report"
        ? "last reported stopped at ${train.current.isEmpty ? 'the station' : train.current}"
        : "last reported$place";
    return "$who · $previous, report ${train.ageMin.round()} min old";
  }
}

class _CrossingDetails extends StatelessWidget {
  const _CrossingDetails({required this.rail, required this.onBack});
  final RailController rail;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final gate = rail.selected!, scene = rail.scene;
    final lead = scene?.trains.firstOrNull, gone = scene?.passed.firstOrNull;
    final awaiting = scene?.awaitingUpdate ?? const <AwaitingTrain>[];
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text("Back to crossings"),
        ),
        const SizedBox(height: 16),
        Text("SELECTED CROSSING", style: railEyebrow(colors)),
        const SizedBox(height: 8),
        Text(
          scene?.crossing?.name.isNotEmpty == true
              ? scene!.crossing!.name
              : gate.name.isEmpty
              ? "Level crossing"
              : gate.name,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          "${gate.km.toStringAsFixed(1)} km from your search point",
          style: text.bodySmall?.copyWith(color: colors.muted),
        ),
        if (trackCrossingLabel(gate, rail.gates) case final String track)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              track,
              style: text.bodySmall?.copyWith(color: colors.muted),
            ),
          ),
        if (rail.sceneLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text("Checking this crossing…"),
          )
        else ...[
          if (rail.sceneMessage != null) ...[
            _Notice(rail.sceneMessage!),
            TextButton.icon(
              onPressed: () => rail.openGate(gate),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("Retry crossing check"),
            ),
          ],
          if (scene?.mapWarning.isNotEmpty == true && rail.sceneMessage == null)
            _Notice(mapWarningLabel(scene!.mapAgeSeconds)),
          if (rail.sceneHistorical && scene?.savedAt != null)
            _Notice(
              "Saved view · ${scene?.savedAt?.toLocal()}. Timings describe that check.",
            ),
          if (scene?.coverage?.notice case final String notice) _Notice(notice),
          _AwaitingUpdates(awaiting),
          _OperatingUpdates(scene?.serviceUpdates ?? const []),
          if (scene?.available == true && (lead != null || awaiting.isEmpty))
            Container(
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.all(18),
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(
                  color: lead == null ? colors.line : colors.accent,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rail.sceneHistorical
                        ? "AT LAST CHECK · ESTIMATE"
                        : awaiting.isNotEmpty
                        ? "OTHER REPORTED TRAIN · ESTIMATE"
                        : gone != null
                        ? "NEXT APPROACHING TRAIN · ESTIMATE"
                        : "ESTIMATED BARRIER TIMING",
                    style: railEyebrow(colors),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    lead == null
                        ? (scene!.incomplete
                              ? "The latest check is incomplete"
                              : "No approaching train reported")
                        : lead.status == "closed" &&
                              lead.etaMin <= 0 &&
                              !lead.positionOnSegment
                        ? "Estimated passing window"
                        : gateLabel(lead.etaMin, lead.closesInMin, lead.status),
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (lead != null) ...[
                    Text(
                      "${lead.number} ${lead.name}${lead.startDate.isEmpty ? '' : ' · Started ${lead.startDate}'}",
                      style: text.bodyMedium,
                    ),
                    if (lead.movement == "stopped")
                      Text(
                        "The train was reported stopped. Movement will appear when a moving report is available.",
                        style: text.bodySmall?.copyWith(color: colors.muted),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      lead.observed == false
                          ? "Scheduled estimate"
                          : "${lead.basis == 'timetable' ? 'Timetable estimate' : 'Train report'} ${lead.ageMin.round()} min old at check",
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                    if (lead.bracket.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text("About this estimate"),
                        children: [Text(lead.bracket)],
                      ),
                  ] else
                    Text(
                      "The barrier’s position is unknown.",
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
          if (gone != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                "Recently passed (estimated): ${gone.number} ${gone.name}${gone.startDate.isEmpty ? '' : ' · Started ${gone.startDate}'} · ${passedLabel(gone.agoMin)}",
                style: text.bodySmall?.copyWith(color: colors.muted),
              ),
            ),
        ],
        const SizedBox(height: 16),
        GateActions(key: ValueKey(gate.id), rail: rail, gate: gate),
        if (scene != null)
          CrossingTimeline(scene: scene, historical: rail.sceneHistorical),
      ],
    );
  }
}

class PredictBody extends StatelessWidget {
  const PredictBody({super.key, required this.predict, this.gates = const []});

  final Predict predict;
  final List<Gate> gates;

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
    final grouped = groupApproaches(trainCrossingRows(predict, gates));
    final sightings = lineSightings(predict);
    final passed = predict.passed.take(6).toList();
    if (grouped.isEmpty && sightings.isEmpty && passed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (predict.mapWarning.isNotEmpty)
              _Notice(mapWarningLabel(predict.mapAgeSeconds)),
            if (predict.coverage?.notice case final String notice)
              _Notice(notice),
            _AwaitingUpdates(predict.awaitingUpdate),
            _OperatingUpdates(predict.serviceUpdates),
            if (predict.awaitingUpdate.isEmpty &&
                predict.serviceUpdates.isEmpty)
              Text(
                predict.incomplete
                    ? "Some train checks are incomplete. The barrier’s position is unknown."
                    : "No live trains reported on this stretch right now.",
                style: text.bodyMedium?.copyWith(color: colors.muted),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (predict.mapWarning.isNotEmpty)
          _Notice(mapWarningLabel(predict.mapAgeSeconds)),
        if (predict.coverage?.notice case final String notice) _Notice(notice),
        if (predict.gatePredictions?.any((row) => row.earlierEstimate) == true)
          const _Notice("This list includes estimates from an earlier check."),
        _AwaitingUpdates(predict.awaitingUpdate),
        _OperatingUpdates(predict.serviceUpdates),
        if (grouped.isEmpty && predict.awaitingUpdate.isEmpty)
          Text(
            "No approaching train was found in the available reports. Gate position is unknown.",
            style: text.bodyMedium?.copyWith(color: colors.muted),
          )
        else
          for (final entry in grouped.entries)
            _TrainBlock(
              number: entry.value.first.train,
              rows: entry.value,
              gates: gates,
              otherReported: predict.awaitingUpdate.isNotEmpty,
            ),
        if (passed.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              "Recently passed (${passed.length})",
              style: text.bodyMedium,
            ),
            children: [for (final row in passed) _PassedBlock(row: row)],
          ),
        ],
        if (sightings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              "Other trains on this line (${sightings.length})",
              style: text.bodyMedium,
            ),
            children: [for (final row in sightings) _SightingBlock(row: row)],
          ),
        ],
      ],
    );
  }
}

class _TrainBlock extends StatelessWidget {
  const _TrainBlock({
    required this.number,
    required this.rows,
    required this.gates,
    this.otherReported = false,
  });
  final String number;
  final List<Approach> rows;
  final List<Gate> gates;
  final bool otherReported;
  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    final head = rows.first;
    final crossings = crossingApproaches(rows, gates);
    final gatesById = {for (final gate in gates) gate.id: gate};
    Widget track(Approach row, String label) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: text.bodySmall)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              gateLabel(row.eta, row.closesIn, row.status),
              textAlign: TextAlign.right,
              style: text.bodySmall?.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );
    Widget crossing(CrossingApproaches crossing) {
      if (!crossing.grouped) {
        final row = crossing.rows.first;
        return track(row, row.cluster.isEmpty ? "Level crossing" : row.cluster);
      }
      final earliest = crossing.rows.first;
      final uncertain = crossing.rows.any(
        (row) =>
            row.status == "uncertain" ||
            gateLabel(row.eta, row.closesIn, row.status) ==
                "train timing uncertain",
      );
      return ExpansionTile(
        key: ValueKey("train-crossing:${head.identity}:${crossing.groupId}"),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        dense: true,
        title: Text(crossing.name, style: text.bodySmall),
        subtitle: Text(
          "${crossing.ids.length} track crossings · ${uncertain ? 'Track timing uncertain' : 'Earliest estimate: ${gateLabel(earliest.eta, earliest.closesIn, earliest.status)}'}",
          style: text.bodySmall?.copyWith(color: colors.muted),
        ),
        children: [
          for (final row in crossing.rows)
            track(
              row,
              row.ids.length > 1
                  ? "${row.ids.length} track crossings"
                  : trackCrossingLabel(gatesById[row.ids.firstOrNull], gates) ??
                        "Track crossing",
            ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (otherReported) ...[
            Text("OTHER REPORTED TRAIN · ESTIMATE", style: railEyebrow(colors)),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  "$number ${head.name}${head.startDate.isEmpty ? '' : ' · Started ${head.startDate}'}",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              StatusPip(
                status: head.status,
                label: "Est. ${labelStatus(head.status)}",
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            head.observed == false
                ? "Scheduled estimate"
                : "${head.basis == 'timetable' ? 'Timetable estimate' : 'Train report'}${head.ageMin == null ? '' : ' · ${head.ageMin!.round()} min old at check'}",
            style: text.bodySmall?.copyWith(color: colors.muted),
          ),
          for (final row in crossings.take(2)) crossing(row),
          if (crossings.length > 2)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                "${crossings.length - 2} more crossings",
                style: text.bodySmall,
              ),
              children: crossings.skip(2).map(crossing).toList(),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text("Route and report details", style: text.bodySmall),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(head.name, style: text.bodyMedium),
                    RunLines(copy: runCopy(head.runInfo, showDelay: true)),
                    if (head.bracket.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: Text(
                          head.bracket,
                          style: text.bodySmall?.copyWith(color: colors.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PassedBlock extends StatelessWidget {
  const _PassedBlock({required this.row});

  final Passed row;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    final where = row.cluster.isEmpty ? "a crossing near you" : row.cluster;
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
                  "${row.train} ${row.name}${row.startDate.isEmpty ? '' : ' · Started ${row.startDate}'}",
                  style: text.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              StatusPip(status: "passed", label: labelStatus("passed")),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              "${passedLabel(row.ago)} at $where",
              style: text.bodyMedium?.copyWith(color: colors.muted),
            ),
          ),
        ],
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
                  "${row.number} ${row.name}${row.startDate.isEmpty ? '' : ' · Started ${row.startDate}'}",
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
    final quiet = status == "passed" || status == "later";
    final foreground = status == "closed"
        ? Colors.white
        : (filled
              ? RailColors.inkDark
              : (quiet ? colors.muted : colors.accent));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: filled
            ? null
            : Border.all(color: quiet ? colors.line : colors.amber),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, letterSpacing: 0.4),
      ),
    );
  }
}

class _GateGroupRow extends StatelessWidget {
  const _GateGroupRow({super.key, required this.crossing, required this.rail});
  final PhysicalCrossing crossing;
  final RailController rail;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    final timed = crossing.timed.firstOrNull;
    final uncertain = crossing.uncertainCount;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: crossing.active ? colors.accent : colors.line,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(crossing.name, style: text.bodyMedium),
        subtitle: Text(
          [
            "${crossing.members.length} track crossings · ${crossing.km.toStringAsFixed(1)} km away",
            if (uncertain > 0)
              "Position update needed on $uncertain ${uncertain == 1 ? 'track' : 'tracks'}",
            if (timed != null)
              "${timed.earlierEstimate
                  ? 'Previous track estimate'
                  : uncertain > 0 && !timed.hasUncertainTrain
                  ? 'Other track estimate'
                  : 'Earliest track estimate'}: ${gateLabel(timed.eta!, timed.closesIn, timed.status)}",
          ].join("\n"),
          style: text.bodySmall?.copyWith(color: colors.muted),
        ),
        children: [
          for (var i = 0; i < crossing.members.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _GateRow(
                gate: crossing.members[i],
                label: trackCrossingLabel(
                  crossing.members[i],
                  crossing.members,
                ),
                selected: crossing.members[i].id == rail.selected?.id,
                onTap: () => rail.openGate(crossing.members[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _GateRow extends StatelessWidget {
  const _GateRow({
    required this.gate,
    required this.selected,
    required this.onTap,
    this.label,
  });
  final Gate gate;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    final uncertain = gate.hasUncertainTrain || gate.status == "uncertain";
    final hot = gate.eta != null || uncertain;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected || hot ? colors.accent : colors.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hot
                      ? colors.amber
                      : colors.muted.withValues(alpha: .5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ??
                          (gate.name.isEmpty ? "Level crossing" : gate.name),
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        "${gate.km.toStringAsFixed(1)} km away",
                        if (gate.eta != null)
                          "${gate.earlierEstimate ? 'Earlier estimate' : 'Est.'} ${gateLabel(gate.eta!, gate.closesIn, gate.status)}",
                        if (uncertain) "Position update needed",
                      ].join(" · "),
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: colors.muted),
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

class CrossingTimeline extends StatelessWidget {
  const CrossingTimeline({
    super.key,
    required this.scene,
    required this.historical,
  });
  final Scene scene;
  final bool historical;
  @override
  Widget build(BuildContext context) {
    final rows = [...scene.trains]
      ..sort((a, b) => a.etaMin.compareTo(b.etaMin));
    if (rows.length < 2) return const SizedBox.shrink();
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            historical
                ? "TRAINS AT THIS SAVED CHECK"
                : scene.awaitingUpdate.isNotEmpty
                ? "OTHER REPORTED TRAINS AT THIS CROSSING"
                : "NEXT TRAINS AT THIS CROSSING",
            style: railEyebrow(colors),
          ),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${row.number} ${row.name}${row.startDate.isEmpty ? '' : ' · Started ${row.startDate}'}",
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    row.etaMin <= 0
                        ? "Estimated to be passing"
                        : row.etaMin < 1
                        ? "Estimated train arrival within 1 min"
                        : "Train arrival in about ${row.etaMin.round()} min",
                    style: text.bodySmall?.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(
            "Uses the same crossing check as the timing above. Reopening time is unknown.",
            style: text.bodySmall?.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class _OperatingUpdates extends StatelessWidget {
  const _OperatingUpdates(this.updates);
  final List<ServiceUpdate> updates;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final row in updates)
        _Notice(
          "${row.number}${row.startDate.isEmpty ? '' : ' · Started ${row.startDate}'} · ${row.status == 'cancelled'
              ? 'Cancelled'
              : row.status == 'diverted'
              ? 'Diverted'
              : 'Partially cancelled'}${row.status == 'cancelled' ? '' : ' · Crossing timing is unavailable until this journey’s route is confirmed.'}",
        ),
    ],
  );
}
