import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../../medications/logic/medication_reorder.dart";
import "../../medications/models/care_group_medication.dart";
import "../../medications/models/medication_care_group_settings.dart";
import "../../medications/repository/medication_care_group_settings_repository.dart";
import "../../medications/repository/medications_repository.dart";

/// In-app alert when the care group’s soonest medication is within the reorder lead window.
class HomeMedicationReorderBanner extends StatefulWidget {
  const HomeMedicationReorderBanner({
    super.key,
    required this.careGroupDataId,
    required this.medicationsRepository,
    required this.settingsRepository,
  });

  final String careGroupDataId;
  final MedicationsRepository medicationsRepository;
  final MedicationCareGroupSettingsRepository settingsRepository;

  @override
  State<HomeMedicationReorderBanner> createState() =>
      _HomeMedicationReorderBannerState();
}

class _HomeMedicationReorderBannerState extends State<HomeMedicationReorderBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed || !widget.medicationsRepository.isAvailable) {
      return const SizedBox.shrink();
    }
    final cg = widget.careGroupDataId;
    return StreamBuilder<List<CareGroupMedication>>(
      stream: widget.medicationsRepository.watchMedications(cg),
      builder: (context, medSnap) {
        return StreamBuilder<MedicationInventoryCareGroupSettings>(
          stream: widget.settingsRepository.watchSettings(cg),
          builder: (context, setSnap) {
            final meds = medSnap.data ?? const <CareGroupMedication>[];
            final settings =
                setSnap.data ?? const MedicationInventoryCareGroupSettings();
            if (!shouldNudgeBatchReorder(meds, settings)) {
              return const SizedBox.shrink();
            }
            final batch = medicationsToReorderInWindow(meds, settings);
            if (batch.isEmpty) {
              return const SizedBox.shrink();
            }
            final names = batch.map((e) => e.name.trim().isEmpty ? "Medication" : e.name.trim()).toList();
            final summary = _nameSummary(names);
            final lead = settings.reorderLeadDays;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => context.push("/medications"),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Time to reorder medications",
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                lead > 0
                                    ? "At least one item is within your $lead-day reorder window. "
                                        "Consider restocking: $summary"
                                    : "Consider restocking soon: $summary",
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: "Dismiss",
                          onPressed: () => setState(() => _dismissed = true),
                          icon: const Icon(Icons.close),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _nameSummary(List<String> names) {
    if (names.isEmpty) {
      return "";
    }
    if (names.length == 1) {
      return names.first;
    }
    if (names.length == 2) {
      return "${names[0]} and ${names[1]}";
    }
    return "${names[0]}, ${names[1]}, and ${names.length - 2} more";
  }
}
