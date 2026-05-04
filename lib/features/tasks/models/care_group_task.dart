import "package:cloud_firestore/cloud_firestore.dart";

/// Maps `careGroups/{careGroupId}/tasks/{taskId}` (rules require title, status, createdBy, createdAt).
final class CareGroupTask {
  const CareGroupTask({
    required this.id,
    required this.title,
    required this.status,
    required this.createdBy,
    this.createdAt,
    this.assignedTo,
    this.notes = "",
    this.dueAt,
    this.size = CareGroupTask.tierMedium,
    this.urgency = CareGroupTask.tierMedium,
    this.attachmentUrls = const [],
  });

  static const String tierLow = "low";
  static const String tierMedium = "medium";
  static const String tierHigh = "high";

  final String id;
  final String title;
  final String status;
  final String createdBy;
  final DateTime? createdAt;
  final String? assignedTo;
  final String notes;
  final DateTime? dueAt;
  /// Effort / scope: `low` | `medium` | `high`.
  final String size;
  /// Importance / time sensitivity: `low` | `medium` | `high`.
  final String urgency;
  final List<String> attachmentUrls;

  static List<String> _stringList(Object? v) {
    if (v is! List) return const [];
    return v.map((e) => e.toString()).toList(growable: false);
  }

  static String _normalizeTier(Object? raw, String fallback) {
    if (raw == null) {
      return fallback;
    }
    final s = (raw is String ? raw : raw.toString()).trim().toLowerCase();
    if (s == tierLow || s == tierMedium || s == tierHigh) {
      return s;
    }
    return fallback;
  }

  static CareGroupTask fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final created = data["createdAt"];
    final due = data["dueAt"];
    return CareGroupTask(
      id: d.id,
      title: (data["title"] as String?)?.trim() ?? "",
      status: (data["status"] as String?)?.trim() ?? "open",
      createdBy: (data["createdBy"] as String?) ?? "",
      createdAt: created is Timestamp ? created.toDate() : null,
      assignedTo: (data["assignedTo"] as String?)?.trim(),
      notes: (data["notes"] as String?)?.trim() ?? "",
      dueAt: due is Timestamp ? due.toDate() : null,
      size: _normalizeTier(data["size"], tierMedium),
      urgency: _normalizeTier(data["urgency"], tierMedium),
      attachmentUrls: _stringList(data["attachmentUrls"]),
    );
  }

  bool get isDone => status == "done" || status == "completed";
}
