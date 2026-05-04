import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../models/care_group_medication.dart";
import "../repository/medications_repository.dart";
import "medication_dose_route_args.dart";

class MedicationDoseConfirmScreen extends StatefulWidget {
  const MedicationDoseConfirmScreen({super.key});

  @override
  State<MedicationDoseConfirmScreen> createState() => _MedicationDoseConfirmScreenState();
}

class _MedicationDoseConfirmScreenState extends State<MedicationDoseConfirmScreen> {
  List<CareGroupMedication> _list = const [];
  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final args = GoRouterState.of(context).extra;
    if (args is! MedicationDoseRouteArgs) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Missing dose details.";
        });
      }
      return;
    }
    final repo = context.read<MedicationsRepository>();
    if (!repo.isAvailable) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Cloud data is not available.";
        });
      }
      return;
    }
    try {
      final list = await repo.fetchMedicationsByIds(
        careGroupId: args.careGroupId,
        medicationIds: args.medicationIds,
      );
      if (mounted) {
        setState(() {
          _list = list;
          _loading = false;
        });
      }
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
  Widget build(BuildContext context) {
    if (_error != null && _list.isEmpty && !_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Dose confirmation")),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!))),
      );
    }
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final args = GoRouterState.of(context).extra;
    if (args is! MedicationDoseRouteArgs) {
      return const Scaffold(body: Center(child: Text("Missing dose details.")));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Did you take these?"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Your care group expects a confirmation for this scheduled dose. "
            "On-hand stock has already been reduced when the dose was due (using entered stock, or the 28-day estimate). "
            "Tap below only if the medicines were actually taken — this records your confirmation only. "
            "If you skip confirming, principal carers can be notified after a grace period.",
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          for (final m in _list) ...[
            ListTile(
              title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: m.dosage.isNotEmpty ? Text(m.dosage) : null,
            ),
            const Divider(),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || _list.isEmpty
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await context.read<MedicationsRepository>().applyDoseDecrements(
                            careGroupId: args.careGroupId,
                            medicationIds: args.medicationIds.toSet(),
                            slotKey: args.slotKey,
                          );
                      if (context.mounted) {
                        context.pop(true);
                      }
                    } catch (e) {
                      if (context.mounted) {
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
                : const Text("Yes, I took these"),
          ),
          TextButton(
            onPressed: _saving ? null : () => context.pop(false),
            child: const Text("Not now"),
          ),
        ],
      ),
    );
  }
}
