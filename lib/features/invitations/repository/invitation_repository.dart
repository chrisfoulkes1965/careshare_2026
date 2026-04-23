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
    required String householdId,
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
      "householdId": householdId,
      "invitedEmail": trimmed,
      "invitedBy": uid,
      "status": "pending",
      "createdAt": FieldValue.serverTimestamp(),
    });
  }
}
