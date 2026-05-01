import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../models/care_group_medication.dart";
import "../models/medication_batch_prep_doc.dart";
import "../repository/medications_repository.dart";

/// Weekly batch preparation checklist (e.g. blister packs): mark each med processed for this week.
class MedicationBatchPrepSheet extends StatelessWidget {
  const MedicationBatchPrepSheet({
    super.key,
    required this.careGroupId,
    required this.medications,
  });

  final String careGroupId;
  final List<CareGroupMedication> medications;

  static Future<void> show(
    BuildContext context, {
    required String careGroupId,
    required List<CareGroupMedication> medications,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => MedicationBatchPrepSheet(
        careGroupId: careGroupId,
        medications: medications,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<MedicationsRepository>();
    if (!repo.isAvailable) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text("Cloud data is not available."),
      );
    }
    final weekKey = MedicationsRepository.currentBatchPrepWeekKey(DateTime.now());
    return StreamBuilder<MedicationBatchPrepDoc>(
      stream: repo.watchMedicationBatchPrep(careGroupId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final doc = snap.data;
        final effective = doc == null || doc.weekKey != weekKey
            ? MedicationBatchPrepDoc(weekKey: weekKey, completedMedicationIds: const [])
            : doc;
        final done = effective.completedMedicationIds.toSet();
        final meds = [...medications]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final maxH = MediaQuery.sizeOf(context).height * 0.55;
        return SizedBox(
          height: maxH,
          child: _MedicationBatchPrepContent(
            careGroupId: careGroupId,
            weekKey: weekKey,
            medications: meds,
            completed: done,
          ),
        );
      },
    );
  }
}

class _MedicationBatchPrepContent extends StatefulWidget {
  const _MedicationBatchPrepContent({
    required this.careGroupId,
    required this.weekKey,
    required this.medications,
    required this.completed,
  });

  final String careGroupId;
  final String weekKey;
  final List<CareGroupMedication> medications;
  final Set<String> completed;

  @override
  State<_MedicationBatchPrepContent> createState() => _MedicationBatchPrepContentState();
}

class _MedicationBatchPrepContentState extends State<_MedicationBatchPrepContent> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final done = widget.completed;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        top: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Weekly batch prep", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Check off each medication as you prepare it for the week (week of ${widget.weekKey}). "
            "Progress is saved for your care team.",
            style: const TextStyle(fontSize: 13),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: widget.medications.length,
              itemBuilder: (context, i) {
                final m = widget.medications[i];
                final checked = done.contains(m.id);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (v) async {
                    if (v == null) {
                      return;
                    }
                    setState(() => _error = null);
                    final next = Set<String>.from(done);
                    if (v) {
                      next.add(m.id);
                    } else {
                      next.remove(m.id);
                    }
                    try {
                      await context.read<MedicationsRepository>().saveMedicationBatchPrep(
                            careGroupId: widget.careGroupId,
                            weekKey: widget.weekKey,
                            completedMedicationIds: next.toList(),
                          );
                    } catch (e) {
                      if (mounted) {
                        setState(() => _error = e.toString());
                      }
                    }
                  },
                  title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: m.dosage.isNotEmpty ? Text(m.dosage) : null,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
}
