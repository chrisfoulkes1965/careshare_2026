import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "../../../core/care/role_label.dart";

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
    required List<String> invitedRoles,
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
    final roles = normalizeAssignableCareGroupRoles(invitedRoles);
    if (roles.isEmpty) {
      throw ArgumentError("Choose at least one role.");
    }

    await FirebaseFirestore.instance.collection("invitations").add({
      "careGroupId": careGroupId,
      "dataCareGroupId": dataCareGroupId,
      "invitedEmail": trimmed,
      "invitedBy": uid,
      "invitedRoles": roles,
      "status": "pending",
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  /// True only when the doc exists and [`status`] is `"pending"`.
  /// Used to drop a stale [PendingInvitationStore] id after redemption or deletion.
  Future<bool> invitationIsAwaitingAcceptance(String invitationId) async {
    if (!_firebaseReady) {
      return false;
    }
    final t = invitationId.trim();
    if (t.isEmpty) {
      return false;
    }
    final snap = await FirebaseFirestore.instance
        .collection("invitations")
        .doc(t)
        .get(const GetOptions(source: Source.server));
    if (!snap.exists) {
      return false;
    }
    final st = ((snap.data() ?? {})["status"] as String?)?.trim() ?? "";
    return st == "pending";
  }

  static List<String> _rolesFromFirestore(Map<String, dynamic> d) {
    final raw = d["invitedRoles"];
    if (raw is List) {
      return normalizeAssignableCareGroupRoles(
        raw.map((e) => e.toString()).toList(),
      );
    }
    return const ["carer"];
  }

  /// Records from an email link: adds the user to [careGroups/{careGroupId}/members/{uid}], marks
  /// the invitation [accepted], and the caller should set [UserProfile.activeCareGroupId] to the
  /// returned id. Idempotent if already accepted (returns [careGroupId] again).
  Future<String?> redeemInvitationForSignedInUser({
    required String invitationId,
    required String displayName,
    int? avatarIndex,
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
      final targetRoles = _rolesFromFirestore(dd);
      final dn =
          displayName.trim().isEmpty ? _emailLocal(u.email) : displayName.trim();

      final mref = FirebaseFirestore.instance
          .collection("careGroups")
          .doc(careGroupId)
          .collection("members")
          .doc(u.uid);
      final mes = await txn.get(mref);
      if (mes.exists) {
        final raw = mes.data()?["roles"];
        final existing = raw is List
            ? raw.map((e) => e.toString()).toList()
            : <String>[];
        final merged = mergeRolePreferOrder(existing, targetRoles);
        final patch = <String, dynamic>{"roles": merged, "displayName": dn};
        if (avatarIndex != null && avatarIndex >= 1) {
          patch["avatarIndex"] = avatarIndex;
        }
        txn.update(mref, patch);
      } else {
        txn.set(mref, {
          "roles": targetRoles,
          "displayName": dn,
          "joinedAt": FieldValue.serverTimestamp(),
          "kudosScore": 0,
          if (avatarIndex != null && avatarIndex >= 1) "avatarIndex": avatarIndex,
        });
      }
      txn.update(iref, {"status": "accepted"});
    });

    return cg;
  }

  /// Union of [existing] and [incoming], ordered by [kAssignableCareGroupRoles].
  static List<String> mergeRolePreferOrder(
    List<String> existing,
    List<String> incoming,
  ) {
    final want = <String>{...existing, ...incoming};
    final out = <String>[];
    for (final r in kAssignableCareGroupRoles) {
      if (want.contains(r)) {
        out.add(r);
      }
    }
    for (final r in want) {
      if (!out.contains(r)) {
        out.add(r);
      }
    }
    return out.isEmpty ? const ["carer"] : out;
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
