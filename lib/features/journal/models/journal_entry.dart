import "package:cloud_firestore/cloud_firestore.dart";

/// `careGroups/{careGroupId}/journalEntries/{id}` — carers and principal can read/write;
/// "receives care only" members cannot read (see firestore.rules).
final class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.title,
    required this.createdBy,
    this.body,
    this.createdAt,
  });

  final String id;
  final String title;
  final String createdBy;
  final String? body;
  final DateTime? createdAt;

  static JournalEntry fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final created = data["createdAt"];
    return JournalEntry(
      id: d.id,
      title: (data["title"] as String?)?.trim() ?? "",
      createdBy: (data["createdBy"] as String?) ?? "",
      body: (data["body"] as String?)?.trim(),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}
