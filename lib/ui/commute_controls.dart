import "package:flutter/material.dart";

import "../commutes.dart";
import "../device_store.dart";
import "../format.dart";
import "../rail_controller.dart";
import "../theme.dart";

class CommuteControls extends StatelessWidget {
  const CommuteControls({super.key, required this.rail});

  final RailController rail;

  Future<void> _edit(BuildContext context, [SavedCommute? trip]) async {
    final edited = await showDialog<({String name, List<String> gates})>(
      context: context,
      builder: (context) => Theme(
        data: railActionTheme(context),
        child: _CommuteDialog(saved: rail.favorites, trip: trip),
      ),
    );
    if (edited == null || !context.mounted) return;
    final allowed = rail.favorites.map((row) => row.gate.id).toSet();
    await rail.commutes.save(
      edited.name,
      edited.gates.where(allowed.contains).toList(),
      original: trip,
    );
  }

  @override
  Widget build(BuildContext context) {
    final commutes = rail.commutes;
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    final saved = {for (final item in rail.favorites) item.gate.id: item};
    final knownGates = {
      for (final item in rail.favorites) item.gate.id: item.gate,
      for (final item in rail.gates) item.id: item,
    };
    return Theme(
      data: railActionTheme(context),
      child: ListenableBuilder(
        listenable: commutes,
        builder: (context, _) {
          if (saved.isEmpty && commutes.trips.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              Text("Commute Check", style: text.titleMedium),
              const SizedBox(height: 8),
              if (commutes.trips.isEmpty)
                Text(
                  "Choose the saved gates you pass on a regular trip.",
                  style: text.bodyMedium?.copyWith(color: colors.muted),
                ),
              for (final trip in commutes.trips)
                Container(
                  key: ValueKey(trip.id),
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(trip.name, style: text.titleMedium),
                          ),
                          PopupMenuButton<String>(
                            tooltip: "Manage ${trip.name}",
                            onSelected: (action) async {
                              if (action == "edit") {
                                await _edit(context, trip);
                              } else {
                                commutes.remove(trip);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: "edit", child: Text("Edit")),
                              PopupMenuItem(
                                value: "remove",
                                child: Text("Remove"),
                              ),
                            ],
                          ),
                        ],
                      ),
                      for (final id in trip.gateIds)
                        if (saved[id] case final SavedGate item)
                          _CommuteRow(
                            gate: item,
                            scope: trackCrossingLabel(
                              knownGates[id],
                              knownGates.values.toList(),
                            ),
                            result: commutes.results[trip.id]?[id],
                            open: () async {
                              await rail.openSaved(item);
                              final note = rail.selectionNote;
                              if (context.mounted && note != null) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(note)));
                              }
                            },
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              "Removed saved gate · edit this commute",
                              style: text.bodySmall?.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            commutes.checking != null ||
                                rail.checking ||
                                rail.sceneLoading ||
                                !trip.gateIds.any(saved.containsKey)
                            ? null
                            : () => rail.checkCommute(trip),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(
                          commutes.checking == trip.id
                              ? "Checking commute…"
                              : "Check commute",
                        ),
                      ),
                      if (commutes.checking == trip.id)
                        TextButton(
                          onPressed: commutes.cancelCheck,
                          child: const Text("Cancel check"),
                        ),
                    ],
                  ),
                ),
              Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final message in [
                      ?commutes.message,
                      ?commutes.storageMessage,
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          message,
                          style: text.bodySmall?.copyWith(color: colors.warn),
                        ),
                      ),
                  ],
                ),
              ),
              if (saved.isNotEmpty &&
                  commutes.trips.length < SavedCommute.maxTrips)
                TextButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Add commute"),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CommuteRow extends StatelessWidget {
  const _CommuteRow({
    required this.gate,
    required this.scope,
    required this.result,
    required this.open,
  });

  final SavedGate gate;
  final String? scope;
  final CommuteGateCheck? result;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) {
    final display = result;
    final train = display?.nextTrain;
    final text = Theme.of(context).textTheme;
    final colors = RailColors.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(gate.label, style: text.bodyMedium),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: open,
      subtitle: display == null && scope == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (scope != null)
                    Text(
                      scope!,
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  if (display?.notice case final String note)
                    Text(
                      note,
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  if (display != null)
                    Text(
                      "${display.summary}${train == null ? '' : ' · ${train.number}'}",
                    ),
                  if (display?.at case final DateTime at)
                    Text(
                      "${display!.historical ? 'Saved check' : 'Checked'} · ${MaterialLocalizations.of(context).formatShortDate(at.toLocal())} ${TimeOfDay.fromDateTime(at.toLocal()).format(context)}",
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
    );
  }
}

class _CommuteDialog extends StatefulWidget {
  const _CommuteDialog({required this.saved, this.trip});
  final List<SavedGate> saved;
  final SavedCommute? trip;

  @override
  State<_CommuteDialog> createState() => _CommuteDialogState();
}

class _CommuteDialogState extends State<_CommuteDialog> {
  late final TextEditingController _name;
  late final List<String> _chosen;
  late final Map<String, SavedGate> _saved;

  @override
  void initState() {
    super.initState();
    _saved = {for (final row in widget.saved) row.gate.id: row};
    _name = TextEditingController(text: widget.trip?.name);
    _chosen = widget.trip?.gateIds.where(_saved.containsKey).toList() ?? [];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _move(int index, int change) {
    setState(() {
      final id = _chosen.removeAt(index);
      _chosen.insert(index + change, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = RailColors.of(context);
    return AlertDialog(
      title: Text(widget.trip == null ? "Add commute" : "Edit commute"),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: "Commute name"),
            ),
            Text("Gates in travel order", style: text.titleSmall),
            if (_chosen.isEmpty)
              Text(
                "Select up to ${SavedCommute.maxGates} saved gates below.",
                style: text.bodySmall?.copyWith(color: colors.muted),
              ),
            for (final (index, id) in _chosen.indexed)
              Row(
                children: [
                  Expanded(child: Text(_saved[id]!.label)),
                  IconButton(
                    tooltip: "Move ${_saved[id]!.label} up",
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: index == 0 ? null : () => _move(index, -1),
                  ),
                  IconButton(
                    tooltip: "Move ${_saved[id]!.label} down",
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: index == _chosen.length - 1
                        ? null
                        : () => _move(index, 1),
                  ),
                  IconButton(
                    tooltip: "Remove ${_saved[id]!.label} from commute",
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _chosen.removeAt(index)),
                  ),
                ],
              ),
            if (_chosen.length < SavedCommute.maxGates)
              for (final gate in widget.saved)
                if (!_chosen.contains(gate.gate.id))
                  TextButton.icon(
                    onPressed: () => setState(() => _chosen.add(gate.gate.id)),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(gate.label),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  name: _name.text,
                  gates: List<String>.of(_chosen),
                )),
          child: const Text("Save"),
        ),
      ],
    );
  }
}
