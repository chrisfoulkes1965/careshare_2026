import "package:cloud_firestore/cloud_firestore.dart";

/// Top-level `invitations/{id}`.
final class CareInvitation {
  const CareInvitation({
    required this.id,
    required this.careGroupId,
    required this.householdId,
    required this.invitedEmail,
    required this.invitedBy,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String careGroupId;
  final String householdId;
  final String invitedEmail;
  final String invitedBy;
  final String status;
  final DateTime? createdAt;

  static CareInvitation fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final created = data["createdAt"];
    return CareInvitation(
      id: d.id,
      careGroupId: (data["careGroupId"] as String?) ?? "",
      householdId: (data["householdId"] as String?) ?? "",
      invitedEmail: (data["invitedEmail"] as String?)?.toLowerCase() ?? "",
      invitedBy: (data["invitedBy"] as String?) ?? "",
      status: (data["status"] as String?) ?? "pending",
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}
