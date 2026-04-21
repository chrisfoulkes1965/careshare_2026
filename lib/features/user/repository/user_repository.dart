import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

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
