import "package:cloud_firestore/cloud_firestore.dart";

/// `households/{hid}/notes/{id}` — create rule requires [title, type, createdBy, createdAt].
/// Optional: [body], [category] (e.g. `legal` limits read to principal/POA per rules).
final class HouseholdNote {
  const HouseholdNote({
    required this.id,
    required this.title,
    required this.type,
    required this.createdBy,
    this.body,
    this.category,
    this.sensitive,
    this.createdAt,
  });

  final String id;
  final String title;
  final String type;
  final String createdBy;
  final String? body;
  final String? category;
  final bool? sensitive;
  final DateTime? createdAt;

  static HouseholdNote fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final created = data["createdAt"];
    return HouseholdNote(
      id: d.id,
      title: (data["title"] as String?)?.trim() ?? "",
      type: (data["type"] as String?)?.trim() ?? "general",
      createdBy: (data["createdBy"] as String?) ?? "",
      body: (data["body"] as String?)?.trim(),
      category: (data["category"] as String?)?.trim(),
      sensitive: data["sensitive"] as bool?,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}
