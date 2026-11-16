import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../api.dart";
import "../device_store.dart";
import "../models.dart";
import "../rail_controller.dart";
import "../theme.dart";

Future<String?> editGateName(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (context) => _TextDialog(
        title: "Name this saved gate",
        label: "Gate name",
        initial: initial,
        action: "Save",
        maxLength: 80,
      ),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.action,
    this.initial = "",
    this.maxLength,
  });
  final String title, label, action, initial;
  final int? maxLength;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text("Cancel"),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: Text(widget.action),
      ),
    ],
  );
}

class SavedGateControls extends StatelessWidget {
  const SavedGateControls({super.key, required this.rail});
  final RailController rail;
  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rail.favorites.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.bookmark_border, size: 30, color: colors.accent),
                const SizedBox(height: 14),
                Text(
                  "Your regular crossings, together",
                  textAlign: TextAlign.center,
                  style: text.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  "Open a crossing and save it as Home, Office, or a name you choose.",
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: colors.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else ...[
          const SizedBox(height: 18),
          for (final item in rail.favorites)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border.all(color: colors.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(Icons.bookmark_border, color: colors.accent),
                title: Text(item.label),
                subtitle: Text(
                  item.gate.name.isEmpty ? "Level crossing" : item.gate.name,
                ),
                onTap: () => rail.openSaved(item),
                trailing: PopupMenuButton<String>(
                  tooltip: "Manage ${item.label}",
                  onSelected: (action) async {
                    if (action == "remove") {
                      rail.removeSaved(item.gate.id);
                      return;
                    }
                    final label = await editGateName(context, item.label);
                    if (label != null) rail.renameSaved(item, label);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: "rename", child: Text("Rename")),
                    const PopupMenuItem(value: "remove", child: Text("Remove")),
                  ],
                ),
              ),
            ),
          Text(
            "Saved on this device.",
            style: text.bodySmall?.copyWith(color: colors.muted),
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          icon: const Icon(Icons.link, size: 18),
          label: const Text("Open shared crossing link"),
          onPressed: () async {
            final value = await showDialog<String>(
              context: context,
              builder: (context) => const _TextDialog(
                title: "Open crossing link",
                label: "GateAhead or OpenStreetMap link",
                action: "Open",
              ),
            );
            if (value != null && !await rail.openLink(value) && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("That link has no valid crossing coordinates."),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

Future<void> showRailSettings(BuildContext context, RailController rail) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: RailColors.of(context).sheet,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        minChildSize: .4,
        maxChildSize: .9,
        builder: (context, scroll) => AnimatedBuilder(
          animation: rail,
          builder: (context, _) {
            final colors = RailColors.of(context),
                text = Theme.of(context).textTheme;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 12, 12),
                  child: Row(
                    children: [
                      Expanded(child: Text("Settings", style: text.titleLarge)),
                      IconButton(
                        tooltip: "Close settings",
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.line),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(
                      22,
                      22,
                      22,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      Text("Appearance", style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        "Choose the map and app theme.",
                        style: text.bodyMedium?.copyWith(color: colors.muted),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          for (final mode in RailThemeMode.values) ...[
                            if (mode == RailThemeMode.light)
                              const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: mode == colors.mode
                                    ? null
                                    : RailThemeScope.of(context).onToggle,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: mode == colors.mode
                                      ? colors.accent
                                      : colors.ink,
                                  disabledForegroundColor: colors.accent,
                                  side: BorderSide(
                                    color: mode == colors.mode
                                        ? colors.accent
                                        : colors.line,
                                  ),
                                ),
                                child: Text(
                                  mode == RailThemeMode.light
                                      ? "Light"
                                      : "Dark",
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),
                      Divider(color: colors.line),
                      const SizedBox(height: 20),
                      Text("Automatic checks", style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        "Keep reports updated while the app is visible.",
                        style: text.bodyMedium?.copyWith(color: colors.muted),
                      ),
                      RefreshControls(rail: rail),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

class RefreshControls extends StatelessWidget {
  const RefreshControls({super.key, required this.rail});
  final RailController rail;
  @override
  Widget build(BuildContext context) {
    final value = rail.refresh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text("Check every 2 minutes"),
          subtitle: const Text("While the app is visible"),
          value: value.enabled,
          onChanged: rail.place == null
              ? null
              : (on) => rail.setRefresh(value.copyWith(enabled: on)),
        ),
        if (value.enabled) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Only during my commute"),
            value: value.commute,
            onChanged: (on) => rail.setRefresh(value.copyWith(commute: on)),
          ),
          if (value.commute) ...[
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _time(context, true),
                  child: Text("From ${value.start}"),
                ),
                OutlinedButton(
                  onPressed: () => _time(context, false),
                  child: Text("Until ${value.end}"),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Weekdays only"),
              value: value.weekdays,
              onChanged: (on) => rail.setRefresh(value.copyWith(weekdays: on)),
            ),
            const Text("Uses this device’s local time."),
          ],
          if (rail.paused)
            const Text(
              "Automatic checks are paused until the service allows another check.",
            ),
        ],
      ],
    );
  }

  Future<void> _time(BuildContext context, bool start) async {
    final clock = (start ? rail.refresh.start : rail.refresh.end).split(":");
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(clock[0]),
        minute: int.parse(clock[1]),
      ),
    );
    if (picked == null) return;
    final text =
        "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
    rail.setRefresh(
      start
          ? rail.refresh.copyWith(start: text)
          : rail.refresh.copyWith(end: text),
    );
  }
}

class GateActions extends StatefulWidget {
  const GateActions({super.key, required this.rail, required this.gate});
  final RailController rail;
  final Gate gate;
  @override
  State<GateActions> createState() => _GateActionsState();
}

class _GateActionsState extends State<GateActions> {
  List<Map<String, dynamic>> reports = [];
  String? message;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = widget.rail.api;
    if (api is! CommunityApi) return;
    try {
      final rows = await (api as CommunityApi).reports(widget.gate.id);
      if (mounted) setState(() => reports = rows);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rail = widget.rail, gate = widget.gate;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final recent = reports
        .where((row) => (row["expires_at"] as num? ?? 0) > now)
        .take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                if (rail.isSaved(gate)) {
                  rail.removeSaved(gate.id);
                  return;
                }
                final name = await editGateName(
                  context,
                  gate.name.isEmpty ? "My gate" : gate.name,
                );
                if (name != null) rail.saveGate(gate, name);
              },
              icon: Icon(
                rail.isSaved(gate) ? Icons.bookmark : Icons.bookmark_border,
                size: 17,
              ),
              label: Text(rail.isSaved(gate) ? "Saved · remove" : "Save gate"),
            ),
            OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: crossingLink(gate)),
                );
                if (mounted) setState(() => message = "Crossing link copied.");
              },
              child: const Text("Share"),
            ),
            if (rail.api is CommunityApi)
              OutlinedButton(
                onPressed: () async {
                  final rows =
                      await showModalBottomSheet<List<Map<String, dynamic>>>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        backgroundColor: RailColors.of(context).sheet,
                        showDragHandle: true,
                        builder: (context) => _GateReportSheet(
                          api: rail.api as CommunityApi,
                          gate: gate,
                        ),
                      );
                  if (rows != null && mounted) {
                    setState(() {
                      reports = rows;
                      message = "Report saved for 10 minutes.";
                    });
                  }
                },
                child: const Text("Report"),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            "Community reports${recent.isEmpty ? '' : ' (${recent.length})'}",
          ),
          children: [
            if (recent.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("No recent reports for this crossing."),
              ),
            for (final row in recent)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    "${switch (row['state']) {
                      'open' => 'Gate open',
                      'closed' => 'Gate closed',
                      _ => 'Location reported incorrect',
                    }} · ${((now - (row['at'] as num)) / 60).floor().clamp(0, 10)} min ago",
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Unverified · expire after 10 minutes."),
              ),
            ),
          ],
        ),
        if (message != null)
          Text(message!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _GateReportSheet extends StatefulWidget {
  const _GateReportSheet({required this.api, required this.gate});
  final CommunityApi api;
  final Gate gate;
  @override
  State<_GateReportSheet> createState() => _GateReportSheetState();
}

class _GateReportSheetState extends State<_GateReportSheet> {
  bool _sending = false;
  String? _error;
  Future<void> _submit(String state) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final rows = await widget.api.report(widget.gate, state);
      if (mounted) Navigator.pop(context, rows);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Could not send your report. Try again later.");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      0,
      22,
      24 + MediaQuery.paddingOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Report this crossing",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: "Close report",
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${widget.gate.name.isEmpty ? 'Level crossing' : widget.gate.name} · what can you see right now?",
          ),
          const SizedBox(height: 20),
          for (final entry in {
            "open": "The gate is open",
            "closed": "The gate is closed",
            "wrong_location": "The location is incorrect",
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: _sending ? null : () => _submit(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.value)),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Text("Reports are unverified and expire after 10 minutes."),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text("Sending report…"),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!),
            ),
        ],
      ),
    ),
  );
}
