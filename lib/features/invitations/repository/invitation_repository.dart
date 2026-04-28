import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/care_invitation.dart";

class InvitationRepository {
  InvitationRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  Stream<List<CareInvitation>> watchByCareGroup(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return FirebaseFirestore.instance
        .collection("invitations")
        .where("careGroupId", isEqualTo: careGroupId)
        .snapshots()
        .map((s) {
      final list = s.docs.map(CareInvitation.fromDoc).toList();
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return list;
    });
  }

  Future<void> createInvitation({
    required String careGroupId,
    required String dataCareGroupId,
    required String email,
  }) async {
    if (!_firebaseReady) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final trimmed = email.trim().toLowerCase();
    if (!trimmed.contains("@")) {
      throw ArgumentError("Enter a valid email address.");
    }
    await FirebaseFirestore.instance.collection("invitations").add({
      "careGroupId": careGroupId,
      "dataCareGroupId": dataCareGroupId,
      "invitedEmail": trimmed,
      "invitedBy": uid,
      "status": "pending",
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  /// Records from an email link: adds the user to [careGroups/{careGroupId}/members/{uid}], marks
  /// the invitation [accepted], and the caller should set [UserProfile.activeCareGroupId] to the
  /// returned id. Idempotent if already accepted (returns [careGroupId] again).
  Future<String?> redeemInvitationForSignedInUser({
    required String invitationId,
    required String displayName,
  }) async {
    if (!_firebaseReady) {
      return null;
    }
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      throw StateError("Not signed in.");
    }
    final email = u.email?.toLowerCase().trim();
    if (email == null || email.isEmpty) {
      throw StateError(
        "Your account must have an email address to accept this invitation.",
      );
    }
    final iref =
        FirebaseFirestore.instance.collection("invitations").doc(invitationId);
    final pre = await iref.get();
    if (!pre.exists) {
      return null;
    }
    final d = pre.data() ?? {};
    final invited = (d["invitedEmail"] as String?)?.toLowerCase().trim() ?? "";
    if (invited != email) {
      throw StateError(
        "This invitation was sent to another email address. Sign in with $invited.",
      );
    }
    final cg = (d["careGroupId"] as String?)?.trim();
    if (cg == null || cg.isEmpty) {
      return null;
    }
    final status = (d["status"] as String?)?.trim() ?? "";
    if (status == "declined") {
      return null;
    }
    if (status == "accepted") {
      return cg;
    }

    final dn = displayName.trim().isEmpty ? _emailLocal(u.email) : displayName.trim();

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(iref);
      if (!snap.exists) {
        return;
      }
      final dd = snap.data() ?? {};
      if ((dd["status"] as String?)?.trim() != "pending") {
        return;
      }
      final careGroupId = (dd["careGroupId"] as String?)?.trim();
      if (careGroupId == null || careGroupId.isEmpty) {
        return;
      }
      final mref = FirebaseFirestore.instance
          .collection("careGroups")
          .doc(careGroupId)
          .collection("members")
          .doc(u.uid);
      final mes = await txn.get(mref);
      const adding = "carer";
      if (mes.exists) {
        final raw = mes.data()?["roles"];
        final roles = raw is List
            ? raw.map((e) => e.toString()).toList()
            : <String>[];
        if (!roles.contains(adding)) {
          txn.update(mref, {"roles": FieldValue.arrayUnion([adding])});
        }
      } else {
        txn.set(mref, {
          "roles": [adding],
          "displayName": dn,
          "joinedAt": FieldValue.serverTimestamp(),
          "kudosScore": 0,
        });
      }
      txn.update(iref, {"status": "accepted"});
    });

    return cg;
  }

  static String _emailLocal(String? email) {
    if (email == null || email.isEmpty) {
      return "Member";
    }
    final at = email.indexOf("@");
    if (at <= 0) {
      return "Member";
    }
    return email.substring(0, at);
  }

  /// Removes a pending invitation (principal only; see Firestore rules).
  Future<void> deleteInvitation(String invitationId) async {
    if (!_firebaseReady) return;
    await FirebaseFirestore.instance.collection("invitations").doc(invitationId).delete();
  }

  /// Triggers [onCareInvitationResendEmail] to send the invitation email again.
  Future<void> requestResendInvitationEmail(String invitationId) async {
    if (!_firebaseReady) return;
    await FirebaseFirestore.instance.collection("invitations").doc(invitationId).update({
      "resendEmailRequestedAt": FieldValue.serverTimestamp(),
    });
  }
}
