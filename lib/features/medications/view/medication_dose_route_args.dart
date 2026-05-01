/// [GoRouter] `extra` for [MedicationDoseConfirmScreen].
final class MedicationDoseRouteArgs {
  const MedicationDoseRouteArgs({
    required this.careGroupId,
    required this.medicationIds,
    this.slotKey = "",
  });

  final String careGroupId;
  final List<String> medicationIds;

  /// Matches [medicationReminderAcks] / dose log scheduling key (optional for legacy payloads).
  final String slotKey;
}
