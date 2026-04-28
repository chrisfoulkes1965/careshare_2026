import "package:cloud_firestore/cloud_firestore.dart";

import "../../../core/firebase/firestore_remote_compat.dart";

/// Top-level `invitations/{id}`.
final class CareInvitation {
  const CareInvitation({
    required this.id,
    required this.careGroupId,
    required this.dataCareGroupId,
    required this.invitedEmail,
    required this.invitedBy,
    required this.status,
    this.createdAt,
    this.emailSentAt,
    this.emailDelivery,
    this.emailDeliveryError,
  });

  final String id;
  final String careGroupId;
  final String dataCareGroupId;
  final String invitedEmail;
  final String invitedBy;
  final String status;
  final DateTime? createdAt;

  /// Set by Cloud Function [onCareInvitationCreated] after Resend (or attempted).
  final DateTime? emailSentAt;
  final String? emailDelivery;
  final String? emailDeliveryError;

  /// Short line for list UI (email pipeline).
  String get emailStatusLine {
    final d = emailDelivery?.trim();
    if (d == null || d.isEmpty) {
      return "Email: not updated (deploy Functions + Resend, or ⋮ resend).";
    }
    if (d == "sent") {
      return "Email: sent";
    }
    if (d == "skipped_config") {
      return "Email: not sent (configure Resend for Cloud Functions)";
    }
    if (d == "error") {
      final err = emailDeliveryError?.trim();
      if (err != null && err.isNotEmpty) {
        final short = err.length > 80 ? "${err.substring(0, 80)}…" : err;
        return "Email: failed — $short";
      }
      return "Email: failed";
    }
    return "Email: $d";
  }

  static String _dataGroupIdFrom(Map<String, dynamic> data) {
    final n = (data["dataCareGroupId"] as String?)?.trim();
    if (n != null && n.isNotEmpty) {
      return n;
    }
    final o = data[firestoreInvitationLegacyDataGroupField()] as String?;
    return o?.trim() ?? "";
  }

  static CareInvitation fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final created = data["createdAt"];
    final sent = data["emailSentAt"];
    return CareInvitation(
      id: d.id,
      careGroupId: (data["careGroupId"] as String?) ?? "",
      dataCareGroupId: _dataGroupIdFrom(data),
      invitedEmail: (data["invitedEmail"] as String?)?.toLowerCase() ?? "",
      invitedBy: (data["invitedBy"] as String?) ?? "",
      status: (data["status"] as String?) ?? "pending",
      createdAt: created is Timestamp ? created.toDate() : null,
      emailSentAt: sent is Timestamp ? sent.toDate() : null,
      emailDelivery: (data["emailDelivery"] as String?)?.trim(),
      emailDeliveryError: (data["emailDeliveryError"] as String?)?.trim(),
    );
  }
}
