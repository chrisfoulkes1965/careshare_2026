import "package:cloud_firestore/cloud_firestore.dart";

/// Fields written by Cloud Function [deliverInvitationEmail] for `/sign-in?invite=` landing.
final class InvitationLandingPreview {
  const InvitationLandingPreview({
    required this.invitationId,
    required this.invitedEmail,
    required this.careGroupLabel,
    required this.inviterLabel,
  });

  final String invitationId;
  final String invitedEmail;
  final String careGroupLabel;
  final String inviterLabel;

  static Future<InvitationLandingPreview?> load(String invitationId) async {
    final id = invitationId.trim();
    if (id.isEmpty) {
      return null;
    }
    final snap =
        await FirebaseFirestore.instance.collection("invitations").doc(id).get();
    if (!snap.exists) {
      return null;
    }
    final d = snap.data();
    if (d == null) {
      return null;
    }
    if ((d["status"] as String?)?.trim() != "pending") {
      return null;
    }
    final invited = (d["invitedEmail"] as String?)?.toLowerCase().trim() ?? "";
    if (invited.isEmpty) {
      return null;
    }
    final group = (d["inviteLandingCareGroupName"] as String?)?.trim();
    final inviter = (d["inviteLandingInviterName"] as String?)?.trim();
    return InvitationLandingPreview(
      invitationId: id,
      invitedEmail: invited,
      careGroupLabel: (group != null && group.isNotEmpty) ? group : "a care team",
      inviterLabel: (inviter != null && inviter.isNotEmpty) ? inviter : "Someone",
    );
  }
}
