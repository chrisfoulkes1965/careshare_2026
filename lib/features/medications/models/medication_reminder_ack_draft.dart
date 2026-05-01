/// Upsert payload for [medications_repository.syncMedicationReminderAckExpectations].
final class MedicationReminderAckDraft {
  const MedicationReminderAckDraft({
    required this.slotKey,
    required this.medicationIds,
    required this.dueAtUtc,
  });

  final String slotKey;
  final List<String> medicationIds;
  final DateTime dueAtUtc;
}
