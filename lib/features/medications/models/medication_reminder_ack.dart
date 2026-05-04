import "package:cloud_firestore/cloud_firestore.dart";

final class MedicationReminderAck {
  const MedicationReminderAck({
    required this.id,
    required this.slotKey,
    required this.medicationIds,
    this.dueAt,
    required this.needsConfirmation,
    this.inventoryAdjustedAt,
  });

  final String id;
  final String slotKey;
  final List<String> medicationIds;
  final DateTime? dueAt;
  final bool needsConfirmation;

  /// When on-hand stock was reduced for this scheduled slot (without user confirmation).
  final DateTime? inventoryAdjustedAt;

  static MedicationReminderAck fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final rawIds = m["medicationIds"];
    final ids = <String>[];
    if (rawIds is List) {
      for (final e in rawIds) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) {
          ids.add(s);
        }
      }
    }
    ids.sort();
    final ts = m["dueAt"];
    DateTime? due;
    if (ts is Timestamp) {
      due = ts.toDate();
    }
    final invTs = m["inventoryAdjustedAt"];
    DateTime? invAt;
    if (invTs is Timestamp) {
      invAt = invTs.toDate();
    }
    return MedicationReminderAck(
      id: d.id,
      slotKey: (m["slotKey"] as String?)?.trim() ?? "",
      medicationIds: ids,
      dueAt: due,
      needsConfirmation: m["needsConfirmation"] != false,
      inventoryAdjustedAt: invAt,
    );
  }
}
