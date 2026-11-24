import "package:flutter/material.dart";

import "../device_store.dart";
import "../phone_alerts.dart";
import "../theme.dart";

Future<void> showPhoneAlertSettings(
  BuildContext context,
  PhoneAlerts alerts,
  SavedGate gate,
) => showDialog<void>(
  context: context,
  builder: (context) => Theme(
    data: railActionTheme(context),
    child: _PhoneAlertDialog(alerts: alerts, gate: gate),
  ),
);

class PhoneAlertControls extends StatelessWidget {
  const PhoneAlertControls({super.key, required this.alerts});

  final PhoneAlerts alerts;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    return Theme(
      data: railActionTheme(context),
      child: ListenableBuilder(
        listenable: alerts,
        builder: (context, _) {
          if (!alerts.showControls) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text("Phone alerts", style: text.titleMedium),
              const SizedBox(height: 8),
              Text(
                alerts.hasAlerts
                    ? "Alerts selected for ${alerts.count} saved ${alerts.count == 1 ? 'gate' : 'gates'}."
                    : "Choose Phone alerts from a saved gate’s menu.",
                style: text.bodyMedium?.copyWith(color: colors.muted),
              ),
              if (alerts.hasAlerts) ...[
                Text(switch (alerts.devicePermission) {
                  true => "Device notifications allowed",
                  false => "Device notifications off",
                  null => "Device permission unconfirmed",
                }, style: text.bodySmall?.copyWith(color: colors.muted)),
                Text(
                  "Alert status · ${alerts.badge}",
                  style: text.bodySmall?.copyWith(color: colors.muted),
                ),
                if (alerts.lastConfirmedAt case final DateTime at)
                  Text(
                    "Settings confirmed ${MaterialLocalizations.of(context).formatShortDate(at.toLocal())}",
                    style: text.bodySmall?.copyWith(color: colors.muted),
                  ),
              ],
              _AlertSyncStatus(alerts: alerts),
              Wrap(
                spacing: 8,
                children: [
                  if (alerts.needsAttention)
                    TextButton(
                      onPressed:
                          alerts.saving ||
                              (alerts.hasAlerts && !alerts.canSetUp)
                          ? null
                          : () => alerts.sync(interactive: true),
                      child: const Text("Retry sync"),
                    ),
                  if (alerts.hasAlerts)
                    TextButton(
                      onPressed: alerts.saving ? null : alerts.disconnect,
                      child: const Text("Turn off all phone alerts"),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlertSyncStatus extends StatelessWidget {
  const _AlertSyncStatus({required this.alerts});
  final PhoneAlerts alerts;

  @override
  Widget build(BuildContext context) {
    final String? message = alerts.saving
        ? "Syncing phone alert settings…"
        : alerts.message ??
              (alerts.pending
                  ? "Phone alert changes are waiting to sync."
                  : null);
    return Semantics(
      liveRegion: true,
      child: message == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: RailColors.of(context).warn),
              ),
            ),
    );
  }
}

class _PhoneAlertDialog extends StatefulWidget {
  const _PhoneAlertDialog({required this.alerts, required this.gate});
  final PhoneAlerts alerts;
  final SavedGate gate;

  @override
  State<_PhoneAlertDialog> createState() => _PhoneAlertDialogState();
}

class _PhoneAlertDialogState extends State<_PhoneAlertDialog> {
  String get _gateId => widget.gate.gate.id;
  late PhoneAlertSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings =
        widget.alerts.settingsFor(_gateId) ?? const PhoneAlertSettings();
  }

  TimeOfDay _time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

  Future<void> _pickTime(bool start) async {
    final current = start ? _settings.startMinute : _settings.endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: _time(current),
    );
    if (!mounted || picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    if (minute == (start ? _settings.endMinute : _settings.startMinute)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Choose different times or select All day."),
        ),
      );
      return;
    }
    setState(() {
      _settings = start
          ? _settings.copyWith(startMinute: minute)
          : _settings.copyWith(endMinute: minute);
    });
  }

  Future<void> _save() async {
    final route = ModalRoute.of(context);
    await widget.alerts.save(widget.gate, _settings);
    if (mounted && route?.isCurrent == true && !widget.alerts.pending) {
      Navigator.pop(context);
    }
  }

  Future<void> _turnOff() async {
    final route = ModalRoute.of(context);
    await widget.alerts.remove(_gateId);
    if (mounted && route?.isCurrent == true && !widget.alerts.pending) {
      Navigator.pop(context);
    }
  }

  Widget _warningTime(int minutes, RailColors colors) {
    final selected = _settings.leadMinutes == minutes;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: selected || widget.alerts.saving
            ? null
            : () => setState(() {
                _settings = _settings.copyWith(leadMinutes: minutes);
              }),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          disabledForegroundColor: selected ? colors.accent : colors.muted,
          side: BorderSide(color: selected ? colors.accent : colors.line),
        ),
        child: Text("$minutes min"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context), text = Theme.of(context).textTheme;
    final alerts = widget.alerts;
    return ListenableBuilder(
      listenable: alerts,
      builder: (context, _) {
        final existing = alerts.settingsFor(_gateId);
        final atCapacity =
            existing == null && alerts.count >= PhoneAlerts.maxGates;
        return AlertDialog(
          title: const Text("Phone alerts"),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.gate.label, style: text.titleMedium),
                const SizedBox(height: 8),
                Text(
                  "Get a notification before an estimated closure. GateAhead stores the selected crossing, alert hours and Firebase installation ID to deliver alerts. Your saved nickname stays on this device.",
                  style: text.bodyMedium?.copyWith(color: colors.muted),
                ),
                const SizedBox(height: 16),
                Text("Warning time", style: text.titleSmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final minutes in [5, 10, 15])
                      _warningTime(minutes, colors),
                  ],
                ),
                const SizedBox(height: 16),
                Text("Alert hours · India time", style: text.titleSmall),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("All day"),
                  value: _settings.allDay,
                  onChanged: alerts.saving
                      ? null
                      : (on) => setState(() {
                          _settings = _settings.copyWith(
                            startMinute: on == true ? 0 : 480,
                            endMinute: on == true ? 0 : 600,
                          );
                        }),
                ),
                if (!_settings.allDay)
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: alerts.saving ? null : () => _pickTime(true),
                        child: Text(
                          "From ${_time(_settings.startMinute).format(context)}",
                        ),
                      ),
                      OutlinedButton(
                        onPressed: alerts.saving
                            ? null
                            : () => _pickTime(false),
                        child: Text(
                          "Until ${_time(_settings.endMinute).format(context)}",
                        ),
                      ),
                    ],
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Weekdays only"),
                  value: _settings.weekdaysOnly,
                  onChanged: alerts.saving
                      ? null
                      : (on) => setState(() {
                          _settings = _settings.copyWith(weekdaysOnly: on);
                        }),
                ),
                if (atCapacity)
                  Text(
                    "Phone alerts can be enabled for up to ${PhoneAlerts.maxGates} gates.",
                    style: text.bodySmall?.copyWith(color: colors.warn),
                  ),
                _AlertSyncStatus(alerts: alerts),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: alerts.saving ? null : _turnOff,
                child: const Text("Turn off"),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(alerts.pending ? "Close" : "Cancel"),
            ),
            FilledButton(
              onPressed: alerts.canSetUp && !alerts.saving && !atCapacity
                  ? _save
                  : null,
              child: const Text("Save alerts"),
            ),
          ],
        );
      },
    );
  }
}
