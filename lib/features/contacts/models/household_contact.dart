import "package:cloud_firestore/cloud_firestore.dart";

/// `households/{hid}/contacts/{id}` — shared directory for the care team.
final class HouseholdContact {
  const HouseholdContact({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static HouseholdContact fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final created = data["createdAt"];
    final updated = data["updatedAt"];
    return HouseholdContact(
      id: d.id,
      name: (data["name"] as String?)?.trim() ?? "Contact",
      phone: (data["phone"] as String?)?.trim(),
      email: (data["email"] as String?)?.trim(),
      notes: (data["notes"] as String?)?.trim(),
      createdBy: data["createdBy"] as String?,
      createdAt: created is Timestamp ? created.toDate() : null,
      updatedAt: updated is Timestamp ? updated.toDate() : null,
    );
  }
}
