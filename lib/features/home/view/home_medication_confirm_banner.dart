import "dart:async";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../../medications/repository/medications_repository.dart";
import "../../medications/view/medication_dose_route_args.dart";

/// Prompts carers / care recipients to confirm scheduled doses that are past due.
class HomeMedicationConfirmBanner extends StatefulWidget {
  const HomeMedicationConfirmBanner({
    super.key,
    required this.careGroupDataId,
    required this.medicationsRepository,
  });

  final String careGroupDataId;
  final MedicationsRepository medicationsRepository;

  @override
  State<HomeMedicationConfirmBanner> createState() =>
      _HomeMedicationConfirmBannerState();
}

class _HomeMedicationConfirmBannerState extends State<HomeMedicationConfirmBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.medicationsRepository.isAvailable) {
      return const SizedBox.shrink();
    }
    final cg = widget.careGroupDataId;
    return StreamBuilder(
      stream: widget.medicationsRepository.watchOverdueMedicationAcks(cg),
      builder: (context, snap) {
        final raw = snap.data ?? const [];
        final now = DateTime.now();
        final overdue = raw.where((a) {
          final d = a.dueAt;
          if (d == null) {
            return false;
          }
          return !d.isAfter(now);
        }).toList();
        if (overdue.isEmpty) {
          return const SizedBox.shrink();
        }
        final first = overdue.first;
        final n = overdue.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                if (first.medicationIds.isEmpty) {
                  context.push("/medications");
                  return;
                }
                context.push(
                  "/medication-dose",
                  extra: MedicationDoseRouteArgs(
                    careGroupId: cg,
                    medicationIds: List<String>.from(first.medicationIds),
                    slotKey: first.slotKey,
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n == 1
                                ? "Confirm scheduled medication"
                                : "$n medication confirmations overdue",
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Tap to record that doses were taken. Principal carers are notified if confirmations stay missing.",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
