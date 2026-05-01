import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../../../core/firebase/firestore_remote_compat.dart";
import "../../chat/repository/chat_repository.dart";
import "../models/setup_models.dart";

final class SetupSubmit {
  const SetupSubmit({
    required this.careGroupName,
    required this.careGroupDescription,
    required this.pathwayIds,
    required this.recipients,
    required this.inviteEmails,
    required this.avatarIndex,
    required this.principalDisplayName,
    required this.address,
    required this.addressType,
  });

  final String careGroupName;
  final String careGroupDescription;
  final List<String> pathwayIds;
  final List<RecipientDraft> recipients;
  final List<String> inviteEmails;
  final int? avatarIndex;
  final String principalDisplayName;
  final String address;
  final CareAddressType addressType;
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
    final groupRef = firestore.collection("careGroups").doc();
    final gId = groupRef.id;
    final userRef = firestore.collection("users").doc(uid);
    final now = FieldValue.serverTimestamp();

    final recipientIds = submit.recipients.map((r) => r.id).toList();

    // One [careGroups] document: care team, home/address, recipients, and [members/].
    // Rules allow principal to create [members] for self in the same batch.
    final batch = firestore.batch();

    batch.set(groupRef, {
      "name": submit.careGroupName.trim(),
      "description": submit.careGroupDescription.trim(),
      "recipientIds": recipientIds,
      "pathwayIds": submit.pathwayIds,
      "recipientProfiles": submit.recipients.map((e) => e.toMap()).toList(),
      "address": submit.address.trim(),
      "addressType": submit.addressType.name,
      "createdBy": uid,
      "createdAt": now,
    });

    batch.set(groupRef.collection("members").doc(uid), {
      "roles": ["care_group_administrator", "principal_carer"],
      "displayName": submit.principalDisplayName.trim(),
      "joinedAt": now,
      "kudosScore": 0,
    });

    batch.set(
      groupRef
          .collection("chatChannels")
          .doc(ChatRepository.defaultGeneralChannelId),
      {
        "name": "General",
        "description": "",
        "topic": "general",
        "memberUids": <String>[uid],
        "createdBy": uid,
        "createdAt": now,
      },
    );

    await batch.commit();

    final followUp = firestore.batch();
    for (final email in _normaliseEmails(submit.inviteEmails)) {
      final invRef = firestore.collection("invitations").doc();
      followUp.set(invRef, {
        "careGroupId": gId,
        "dataCareGroupId": gId,
        "invitedEmail": email,
        "invitedBy": uid,
        "invitedRoles": ["carer"],
        "status": "pending",
        "createdAt": now,
      });
    }

    final userUpdate = <String, dynamic>{
      "wizardCompleted": true,
      "wizardSkipped": false,
      "activeCareGroupId": gId,
      firestoreUserLegacyActiveCareGroupField(): FieldValue.delete(),
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
