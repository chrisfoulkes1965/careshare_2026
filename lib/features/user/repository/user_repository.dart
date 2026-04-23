import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../../care_group/models/care_group_option.dart";
import "../models/user_profile.dart";

class UserRepository {
  UserRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      FirebaseFirestore.instance.collection("users").doc(uid);

  Future<UserProfile?> fetchProfile(String uid) async {
    if (!_firebaseReady) return null;
    final snap = await _userRef(uid).get();
    if (!snap.exists) return null;
    return _map(uid, snap.data()!);
  }

  Future<void> ensureUserDocument(User user) async {
    if (!_firebaseReady) return;
    final ref = _userRef(user.uid);
    final snap = await ref.get();
    if (snap.exists) return;

    final email = user.email ?? "";
    final displayName = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : _emailLocalPart(email);

    await ref.set(
      {
        "displayName": displayName,
        "email": email,
        "photoUrl": user.photoURL,
        "avatarIndex": null,
        "phone": null,
        "dateOfBirth": null,
        "simpleMode": false,
        "createdAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: false),
    );
  }

  Future<void> updateProfileFields(String uid, Map<String, dynamic> data) async {
    if (!_firebaseReady) return;
    await _userRef(uid).update(data);
  }

  /// Sets [activeHouseholdId] and [activeCareGroupId] on the user (Firestore field names).
  Future<void> setActiveCareGroup({
    required String uid,
    required String householdId,
    required String careGroupId,
  }) async {
    if (!_firebaseReady) return;
    await _userRef(uid).update({
      "activeHouseholdId": householdId,
      "activeCareGroupId": careGroupId,
    });
  }

  /// Every care group where `members/{uid}` exists; deduped by home id, sorted by name.
  ///
  /// Uses a [collectionGroup] query on `members` and reads linked `careGroups` + `households`
  /// for display names. May require a Firestore index for the collection group query
  /// (the console or CLI will link one if needed).
  Future<List<CareGroupOption>> listCareGroupsForUser(String uid) async {
    if (!_firebaseReady) return const [];

    final membersSnap = await FirebaseFirestore.instance
        .collectionGroup("members")
        .where(FieldPath.documentId, isEqualTo: uid)
        .get();

    if (membersSnap.docs.isEmpty) {
      return const [];
    }

    final byHome = <String, CareGroupOption>{};

    for (final memberDoc in membersSnap.docs) {
      final careGroupRef = memberDoc.reference.parent.parent;
      if (careGroupRef == null) continue;
      final careGroupId = careGroupRef.id;

      final cgSnap = await FirebaseFirestore.instance.collection("careGroups").doc(careGroupId).get();
      if (!cgSnap.exists) continue;
      final cgData = cgSnap.data()!;
      final householdId = cgData["householdId"] as String?;
      if (householdId == null || householdId.isEmpty) continue;
      if (byHome.containsKey(householdId)) continue;

      var name = (cgData["name"] as String?)?.trim() ?? "Care group";
      final hSnap = await FirebaseFirestore.instance.collection("households").doc(householdId).get();
      if (hSnap.exists) {
        final hn = (hSnap.data()?["name"] as String?)?.trim();
        if (hn != null && hn.isNotEmpty) {
          name = hn;
        }
      }
      byHome[householdId] = CareGroupOption(
        householdId: householdId,
        careGroupId: careGroupId,
        displayName: name,
      );
    }

    final list = byHome.values.toList();
    list.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return list;
  }

  UserProfile _map(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      email: (data["email"] as String?) ?? "",
      displayName: (data["displayName"] as String?) ?? "",
      photoUrl: data["photoUrl"] as String?,
      avatarIndex: (data["avatarIndex"] as num?)?.toInt(),
      simpleMode: data["simpleMode"] as bool? ?? false,
      wizardCompleted: data["wizardCompleted"] as bool? ?? false,
      wizardSkipped: data["wizardSkipped"] as bool? ?? false,
      activeHouseholdId: data["activeHouseholdId"] as String?,
      activeCareGroupId: data["activeCareGroupId"] as String?,
      wizardDraft: (data["wizardDraft"] as Map?)?.cast<String, dynamic>(),
    );
  }

  String _emailLocalPart(String email) {
    final at = email.indexOf("@");
    if (at <= 0) return "Carer";
    return email.substring(0, at);
  }
}
