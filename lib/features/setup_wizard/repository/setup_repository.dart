import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/setup_models.dart";

final class SetupSubmit {
  const SetupSubmit({
    required this.householdName,
    required this.householdDescription,
    required this.pathwayIds,
    required this.recipients,
    required this.inviteEmails,
    required this.avatarIndex,
    required this.principalDisplayName,
  });

  final String householdName;
  final String householdDescription;
  final List<String> pathwayIds;
  final List<RecipientDraft> recipients;
  final List<String> inviteEmails;
  final int? avatarIndex;
  final String principalDisplayName;
}

class SetupRepository {
  SetupRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  Future<void> saveDraft(String uid, Map<String, dynamic> draft) async {
    if (!_firebaseReady) return;
    await FirebaseFirestore.instance.collection("users").doc(uid).update({
      "wizardDraft": draft,
    });
  }

  Future<void> skipWizard(String uid) async {
    if (!_firebaseReady) return;
    await FirebaseFirestore.instance.collection("users").doc(uid).update({
      "wizardSkipped": true,
      "wizardCompleted": false,
    });
  }

  Future<void> resumeWizard(String uid) async {
    if (!_firebaseReady) return;
    await FirebaseFirestore.instance.collection("users").doc(uid).update({
      "wizardSkipped": false,
    });
  }

  Future<void> completeWizard({
    required String uid,
    required SetupSubmit submit,
  }) async {
    if (!_firebaseReady) {
      throw StateError("Firebase is not configured.");
    }

    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null || auth.uid != uid) {
      throw StateError("Not signed in.");
    }

    final firestore = FirebaseFirestore.instance;
    final hhRef = firestore.collection("households").doc();
    final hhId = hhRef.id;
    final cgRef = firestore.collection("careGroups").doc();
    final cgId = cgRef.id;
    final userRef = firestore.collection("users").doc(uid);
    final now = FieldValue.serverTimestamp();

    final recipientIds = submit.recipients.map((r) => r.id).toList();

    final coreBatch = firestore.batch();

    coreBatch.set(cgRef, {
      "householdId": hhId,
      "name": submit.householdName.trim(),
      "createdBy": uid,
      "createdAt": now,
    });

    coreBatch.set(cgRef.collection("members").doc(uid), {
      "roles": ["principal_carer"],
      "displayName": submit.principalDisplayName.trim(),
      "joinedAt": now,
      "kudosScore": 0,
    });

    coreBatch.set(hhRef, {
      "name": submit.householdName.trim(),
      "description": submit.householdDescription.trim(),
      "careGroupId": cgId,
      "recipientIds": recipientIds,
      "pathwayIds": submit.pathwayIds,
      "recipientProfiles": submit.recipients.map((e) => e.toMap()).toList(),
      "createdBy": uid,
      "createdAt": now,
    });

    await coreBatch.commit();

    final followUp = firestore.batch();
    for (final email in _normaliseEmails(submit.inviteEmails)) {
      final invRef = firestore.collection("invitations").doc();
      followUp.set(invRef, {
        "careGroupId": cgId,
        "householdId": hhId,
        "invitedEmail": email,
        "invitedBy": uid,
        "status": "pending",
        "createdAt": now,
      });
    }

    final userUpdate = <String, dynamic>{
      "wizardCompleted": true,
      "wizardSkipped": false,
      "activeHouseholdId": hhId,
      "activeCareGroupId": cgId,
      "wizardDraft": FieldValue.delete(),
    };
    if (submit.avatarIndex != null) {
      userUpdate["avatarIndex"] = submit.avatarIndex;
    }

    followUp.update(userRef, userUpdate);
    await followUp.commit();
  }

  List<String> _normaliseEmails(List<String> raw) {
    final out = <String>{};
    for (final e in raw) {
      final t = e.trim().toLowerCase();
      if (t.contains("@")) out.add(t);
    }
    return out.toList();
  }
}
