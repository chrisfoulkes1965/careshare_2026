import "package:cloud_firestore/cloud_firestore.dart";

import "../../../core/care/role_label.dart";
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
    this.invitedRoles = const [],
    this.createdAt,
    this.emailSentAt,
    this.emailDelivery,
    this.emailDeliveryError,
    this.inviteLinkFollowedAt,
    this.inviteRegisteredAt,
    this.inviteSignedInAt,
    this.inviteAcceptedCareGroupAt,
  });

  final String id;
  final String careGroupId;
  final String dataCareGroupId;
  final String invitedEmail;
  final String invitedBy;
  final String status;
  /// Roles the invitee will receive when they accept (stored on [invitations/{id}]).
  final List<String> invitedRoles;
  final DateTime? createdAt;

  /// Set by Cloud Function [onCareInvitationCreated] after Resend (or attempted).
  final DateTime? emailSentAt;
  final String? emailDelivery;
  final String? emailDeliveryError;

  /// Invitee tracked milestones (Firestore). See [inviteOnboardingSubtitle].
  final DateTime? inviteLinkFollowedAt;
  final DateTime? inviteRegisteredAt;
  final DateTime? inviteSignedInAt;
  /// When they completed name/avatar + joined the group (invite redeemed).
  final DateTime? inviteAcceptedCareGroupAt;

  /// Multi-line subtitle for organisers: funnel through invite link → auth → acceptance.
  String get inviteOnboardingSubtitle {
    final linkDone = inviteLinkFollowedAt != null;
    final step2Registered = inviteRegisteredAt != null;
    final step2SignedIn = inviteSignedInAt != null;
    final step3Done = inviteAcceptedCareGroupAt != null || status == "accepted";

    final linkLabel =
        linkDone ? "Opened invite link ✓" : "Opened invite link …";
    String accountLabel;
    if (step2Registered) {
      accountLabel = "Created account ✓";
    } else if (step2SignedIn) {
      accountLabel = "Signed in (existing account) ✓";
    } else {
      accountLabel = status == "pending" ? "Account …" : "Account —";
    }
    final acceptLabel =
        step3Done ? "Accepted invitation & joined group ✓" : "Invitation …";

    return "$linkLabel\n$accountLabel\n$acceptLabel";
  }

  /// One-line summary for tight layouts (home settings snippet).
  String get inviteOnboardingProgressCompact {
    final linkOk = inviteLinkFollowedAt != null;
    final regOk = inviteRegisteredAt != null;
    final signOk = inviteSignedInAt != null;
    final joinOk =
        inviteAcceptedCareGroupAt != null || status == "accepted";

    final linkChunk = linkOk ? "Invite link ✓" : "Invite link …";
    final accountChunk = regOk
        ? "New account ✓"
        : (signOk ? "Signed in ✓" : "Account …");
    final joinChunk =
        joinOk ? "Joined team ✓" : "Invitation …";

    return "$linkChunk · $accountChunk · $joinChunk";
  }

  /// Short line for list UI (email pipeline).
  String get emailStatusLine {
    final d = emailDelivery?.trim();
    if (d == null || d.isEmpty) {
      return "Invite email: status unknown — tap ⋮ then Resend email if they didn’t receive it.";
    }
    if (d == "sent") {
      return "Email sent";
    }
    if (d == "skipped_config") {
      return "Automated invite email isn’t set up — send the link manually or ask your admin.";
    }
    if (d == "error") {
      final err = emailDeliveryError?.trim();
      if (err != null && err.isNotEmpty) {
        final short = err.length > 80 ? "${err.substring(0, 80)}…" : err;
        return "Email failed — $short";
      }
      return "Email failed to send";
    }
    return "Email status: $d";
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
    final rawRoles = data["invitedRoles"];
    final invitedRoles = rawRoles is List
        ? normalizeAssignableCareGroupRoles(
            rawRoles.map((e) => e.toString()).toList(),
          )
        : const <String>["carer"];
    final link = data["inviteLinkFollowedAt"];
    final reg = data["inviteRegisteredAt"];
    final sig = data["inviteSignedInAt"];
    final accepted = data["inviteAcceptedCareGroupAt"];
    return CareInvitation(
      id: d.id,
      careGroupId: (data["careGroupId"] as String?) ?? "",
      dataCareGroupId: _dataGroupIdFrom(data),
      invitedEmail: (data["invitedEmail"] as String?)?.toLowerCase() ?? "",
      invitedBy: (data["invitedBy"] as String?) ?? "",
      status: (data["status"] as String?) ?? "pending",
      invitedRoles: invitedRoles,
      createdAt: created is Timestamp ? created.toDate() : null,
      emailSentAt: sent is Timestamp ? sent.toDate() : null,
      emailDelivery: (data["emailDelivery"] as String?)?.trim(),
      emailDeliveryError: (data["emailDeliveryError"] as String?)?.trim(),
      inviteLinkFollowedAt: link is Timestamp ? link.toDate() : null,
      inviteRegisteredAt: reg is Timestamp ? reg.toDate() : null,
      inviteSignedInAt: sig is Timestamp ? sig.toDate() : null,
      inviteAcceptedCareGroupAt:
          accepted is Timestamp ? accepted.toDate() : null,
    );
  }
}
