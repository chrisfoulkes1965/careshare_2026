import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../models/medication_care_group_settings.dart";
import "../repository/medication_care_group_settings_repository.dart";

class MedicationInventorySettingsSheet extends StatefulWidget {
  const MedicationInventorySettingsSheet({super.key, required this.householdId});

  final String householdId;

  static Future<void> show(BuildContext context, {required String householdId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => MedicationInventorySettingsSheet(householdId: householdId),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<MedicationCareGroupSettingsRepository>();
    try {
      final st = await repo.getSettings(widget.householdId);
      if (!mounted) {
        return;
      }
      _lead.text = "${st.reorderLeadDays}";
      _window.text = "${st.reorderWindowDays}";
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Inventory & reorder", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            "When your soonest medication hits the “reorder lead”, you’ll see one prompt listing every "
            "medication that would run out within the “reorder window” (so you can place a single order).",
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _lead,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Days before stockout to nudge reorder",
              hintText: "e.g. 7",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _window,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Reorder window (days)",
              hintText: "e.g. 14 — include all meds running out within this many days",
            ),
          ),
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
                    setState(() {
                      _saving = true;
                      _error = null;
                    });
                    try {
                      await context.read<MedicationCareGroupSettingsRepository>().saveSettings(
                            widget.householdId,
                            MedicationInventoryCareGroupSettings(
                              reorderLeadDays: la.clamp(0, 90),
                              reorderWindowDays: wi.clamp(0, 180),
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
    );
  }
}
