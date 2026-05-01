import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../models/medication_care_group_settings.dart";
import "../repository/medication_care_group_settings_repository.dart";

class MedicationInventorySettingsSheet extends StatefulWidget {
  const MedicationInventorySettingsSheet({super.key, required this.careGroupId});

  final String careGroupId;

  static Future<void> show(BuildContext context, {required String careGroupId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => MedicationInventorySettingsSheet(careGroupId: careGroupId),
    );
  }

  @override
  State<MedicationInventorySettingsSheet> createState() => _MedicationInventorySettingsSheetState();
}

class _MedicationInventorySettingsSheetState extends State<MedicationInventorySettingsSheet> {
  final _lead = TextEditingController();
  final _window = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _quietEnabled = false;
  TimeOfDay? _quietFrom;
  TimeOfDay? _quietTo;

  static TimeOfDay? _minuteToTime(int? m) {
    if (m == null) {
      return null;
    }
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  static int? _timeToMinute(TimeOfDay? t) {
    if (t == null) {
      return null;
    }
    return t.hour * 60 + t.minute;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<MedicationCareGroupSettingsRepository>();
    try {
      final st = await repo.getSettings(widget.careGroupId);
      if (!mounted) {
        return;
      }
      _lead.text = "${st.reorderLeadDays}";
      _window.text = "${st.reorderWindowDays}";
      _quietFrom = _minuteToTime(st.quietHoursStartMinute);
      _quietTo = _minuteToTime(st.quietHoursEndMinute);
      _quietEnabled = st.quietHoursEnabled;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _lead.dispose();
    _window.dispose();
    super.dispose();
  }

  Future<void> _pickQuietFrom() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _quietFrom ?? const TimeOfDay(hour: 22, minute: 0),
    );
    if (t != null && mounted) {
      setState(() => _quietFrom = t);
    }
  }

  Future<void> _pickQuietTo() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _quietTo ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (t != null && mounted) {
      setState(() => _quietTo = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Inventory & reorder", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              "Set how many days before you expect to run out you want to be reminded to reorder. "
              "The “reorder window” lists every medication that would run out within that many days "
              "so you can place one order.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lead,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Remind me this many days before stock runs out",
                hintText: "e.g. 7 — start nudging when supply is within 7 days",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _window,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Include in the reorder list (days)",
                hintText: "e.g. 14 — show all meds running out within 14 days",
              ),
            ),
            const SizedBox(height: 20),
            Text("Reminder quiet hours", style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(
              "Local medication alerts on this device are shifted out of this window (e.g. overnight). "
              "Uses this care group’s saved times; applies when reminders sync.",
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _quietEnabled,
              onChanged: _saving
                  ? null
                  : (v) {
                      setState(() {
                        _quietEnabled = v;
                        if (v && (_quietFrom == null || _quietTo == null)) {
                          _quietFrom ??= const TimeOfDay(hour: 22, minute: 0);
                          _quietTo ??= const TimeOfDay(hour: 7, minute: 0);
                        }
                      });
                    },
              title: const Text("Suppress alerts during a daily window"),
            ),
            if (_quietEnabled) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("From"),
                subtitle: Text(_quietFrom?.format(context) ?? "—"),
                trailing: const Icon(Icons.schedule),
                onTap: _saving ? null : _pickQuietFrom,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Until"),
                subtitle: Text(_quietTo?.format(context) ?? "—"),
                trailing: const Icon(Icons.schedule),
                onTap: _saving ? null : _pickQuietTo,
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          _quietEnabled = false;
                          _quietFrom = null;
                          _quietTo = null;
                        });
                      },
                child: const Text("Clear quiet hours"),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final la = int.tryParse(_lead.text.trim());
                      final wi = int.tryParse(_window.text.trim());
                      if (la == null || wi == null) {
                        setState(() => _error = "Enter whole numbers.");
                        return;
                      }
                      if (_quietEnabled && (_quietFrom == null || _quietTo == null)) {
                        setState(() => _error = "Pick both start and end times for quiet hours, or turn the feature off.");
                        return;
                      }
                      if (_quietEnabled && _timeToMinute(_quietFrom) == _timeToMinute(_quietTo)) {
                        setState(() => _error = "Start and end must differ (use overnight e.g. 22:00 → 07:00).");
                        return;
                      }
                      setState(() {
                        _saving = true;
                        _error = null;
                      });
                      try {
                        final qs = _quietEnabled ? _timeToMinute(_quietFrom) : null;
                        final qe = _quietEnabled ? _timeToMinute(_quietTo) : null;
                        await context.read<MedicationCareGroupSettingsRepository>().saveSettings(
                              widget.careGroupId,
                              MedicationInventoryCareGroupSettings(
                                reorderLeadDays: la.clamp(0, 90),
                                reorderWindowDays: wi.clamp(0, 180),
                                quietHoursStartMinute: qs,
                                quietHoursEndMinute: qe,
                              ),
                            );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _saving = false;
                            _error = e.toString();
                          });
                        }
                      }
                    },
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}
