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
    this.attachmentUrls = const [],
  });

  final String id;
  final String title;
  final String status;
  final String createdBy;
  final DateTime? createdAt;
  final String? assignedTo;
  final String notes;
  final DateTime? dueAt;
  final List<String> attachmentUrls;

  static List<String> _stringList(Object? v) {
    if (v is! List) return const [];
    return v.map((e) => e.toString()).toList(growable: false);
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
      attachmentUrls: _stringList(data["attachmentUrls"]),
    );
  }

  bool get isDone => status == "done" || status == "completed";
}
