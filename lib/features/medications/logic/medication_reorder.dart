import "../models/household_medication.dart";
import "../models/medication_care_group_settings.dart";

List<CareGroupMedication> medicationsToReorderInWindow(
  List<CareGroupMedication> meds,
  MedicationInventoryCareGroupSettings s,
) {
  final m = <CareGroupMedication>[];
  for (final e in meds) {
    if (!e.reminderEnabled) {
      continue;
    }
    if (!e.hasValidReminderSchedule) {
      continue;
    }
    final d = e.estimatedDaysOfSupply;
    if (d == null) {
      continue;
    }
    if (d > 0 && d <= s.reorderWindowDays) {
      m.add(e);
    }
  }
  m.sort(
    (a, b) {
      final da = a.estimatedDaysOfSupply ?? 999;
      final db = b.estimatedDaysOfSupply ?? 999;
      return da.compareTo(db);
    },
  );
  return m;
}

/// True when the soonest depletion is within [s.reorderLeadDays] (reorder nudge time).
bool shouldNudgeBatchReorder(
  List<CareGroupMedication> meds,
  MedicationInventoryCareGroupSettings s,
) {
  double? minD;
  for (final e in meds) {
    if (!e.reminderEnabled) {
      continue;
    }
    if (!e.hasValidReminderSchedule) {
      continue;
    }
    final d = e.estimatedDaysOfSupply;
    if (d == null || d < 0) {
      continue;
    }
    if (minD == null || d < minD) {
      minD = d;
    }
  }
  if (minD == null) {
    return false;
  }
  return minD > 0 && minD <= s.reorderLeadDays;
}
