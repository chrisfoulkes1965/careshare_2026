import "package:cloud_firestore/cloud_firestore.dart";

/// One `careGroups/.../medications/{id}/doseLogs/{logId}` entry (append-only audit).
final class MedicationDoseLogEntry {
  const MedicationDoseLogEntry({
    required this.id,
    required this.loggedBy,
    this.takenAt,
    this.slotKey,
    this.scheduledDeduction = false,
  });

  final String id;
  final String loggedBy;
  final DateTime? takenAt;
  final String? slotKey;

  /// True when stock was reduced because the scheduled dose was due (not a user confirmation).
  final bool scheduledDeduction;

  static MedicationDoseLogEntry fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final ts = m["takenAt"];
    DateTime? taken;
    if (ts is Timestamp) {
      taken = ts.toDate();
    }
    final sk = m["slotKey"];
    return MedicationDoseLogEntry(
      id: d.id,
      loggedBy: (m["loggedBy"] as String?)?.trim() ?? "",
      takenAt: taken,
      slotKey: sk is String ? sk.trim() : null,
      scheduledDeduction: m["scheduledDeduction"] == true,
    );
  }
}
