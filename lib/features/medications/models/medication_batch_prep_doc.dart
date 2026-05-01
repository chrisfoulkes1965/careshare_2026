/// `careGroups/{cid}/medicationBatchPrep/current` — weekly batch-prep checklist.
final class MedicationBatchPrepDoc {
  const MedicationBatchPrepDoc({
    required this.weekKey,
    required this.completedMedicationIds,
  });

  final String weekKey;
  final List<String> completedMedicationIds;

  static MedicationBatchPrepDoc fromMap(Map<String, dynamic> data) {
    final wk = (data["weekKey"] as String?)?.trim() ?? "";
    final raw = data["completedMedicationIds"];
    final ids = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.isNotEmpty) {
          ids.add(e);
        }
      }
    }
    ids.sort();
    return MedicationBatchPrepDoc(weekKey: wk, completedMedicationIds: ids);
  }
}
