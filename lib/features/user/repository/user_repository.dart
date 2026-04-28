import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../../../core/firebase/firestore_remote_compat.dart";
import "../../care_group/models/care_group_option.dart";
import "../models/user_profile.dart";

class UserRepository {
  UserRepository({required bool firebaseReady})
      : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      FirebaseFirestore.instance.collection("users").doc(uid);

  CollectionReference<Map<String, dynamic>> _devicePushTokens(String uid) =>
      _userRef(uid).collection("devicePushTokens");

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

  Future<void> updateProfileFields(
      String uid, Map<String, dynamic> data) async {
    if (!_firebaseReady) return;
    await _userRef(uid).update(data);
  }

  /// One document per app install (see [installationId]). Used by Cloud Functions for FCM.
  Future<void> upsertDevicePushToken({
    required String uid,
    required String installationId,
    required String token,
    required String platform,
  }) async {
    if (!_firebaseReady) return;
    await _devicePushTokens(uid).doc(installationId).set(
      {
        "token": token,
        "platform": platform,
        "updatedAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> removeDevicePushToken({
    required String uid,
    required String installationId,
  }) async {
    if (!_firebaseReady) return;
    await _devicePushTokens(uid).doc(installationId).delete();
  }

  /// Use a built-in avatar; clears [photoUrl] in Firestore so the preset shows in the app.
  Future<void> setAvatarPreset(String uid, int oneBasedIndex) async {
    if (!_firebaseReady) return;
    await _userRef(uid).update({
      "avatarIndex": oneBasedIndex,
      "photoUrl": FieldValue.delete(),
    });
  }

  /// Sets the profile image from a URL, or removes it; clears [avatarIndex] when a URL is set.
  Future<void> setProfilePhotoUrl(String uid, String? url) async {
    if (!_firebaseReady) return;
    if (url == null || url.trim().isEmpty) {
      await _userRef(uid).update({
        "photoUrl": FieldValue.delete(),
      });
    } else {
      await _userRef(uid).update({
        "photoUrl": url.trim(),
        "avatarIndex": FieldValue.delete(),
      });
    }
  }

  /// Adds a care recipient who does not use the app to [recipientIds] / [recipientProfiles]
  /// on the home [careGroups] document (principal carer per rules).
  ///
  /// [dataCareGroupDocId] is [ProfileReady.activeCareGroupDataId] — the document that holds
  /// home metadata and the recipient list from setup.
  Future<void> addOfflineCareRecipient({
    required String dataCareGroupDocId,
    required String displayName,
  }) async {
    if (!_firebaseReady) return;
    final t = displayName.trim();
    if (t.isEmpty) {
      throw ArgumentError("Enter a name.");
    }
    final ref = FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataCareGroupDocId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError("Care group not found.");
      }
      final data = snap.data() ?? {};
      final rawIds = data["recipientIds"];
      final rawProfiles = data["recipientProfiles"];
      final ids = <String>[
        ...?((rawIds as List?)?.map((e) => e.toString())),
      ];
      final profiles = <Map<String, dynamic>>[
        ...?((rawProfiles as List?)?.map(
          (e) => Map<String, dynamic>.from(e as Map),
        )),
      ];
      final id = "rcp_${DateTime.now().microsecondsSinceEpoch}";
      ids.add(id);
      profiles.add({
        "id": id,
        "displayName": t,
        "accessMode": "managed",
      });
      tx.update(ref, {
        "recipientIds": ids,
        "recipientProfiles": profiles,
      });
    });
  }

  /// Removes one entry from [recipientIds] / [recipientProfiles] on the home [careGroups] doc.
  Future<void> removeOfflineCareRecipient({
    required String dataCareGroupDocId,
    required String recipientId,
  }) async {
    if (!_firebaseReady) return;
    if (recipientId.isEmpty) {
      throw ArgumentError("Missing recipient id.");
    }
    final ref = FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataCareGroupDocId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError("Care group not found.");
      }
      final data = snap.data() ?? {};
      final rawIds = data["recipientIds"];
      final rawProfiles = data["recipientProfiles"];
      final ids = <String>[
        ...?((rawIds as List?)?.map((e) => e.toString())),
      ];
      final profiles = <Map<String, dynamic>>[
        ...?((rawProfiles as List?)?.map(
          (e) => Map<String, dynamic>.from(e as Map),
        )),
      ];
      final nextIds = ids.where((e) => e != recipientId).toList();
      final nextProfiles = profiles
          .where(
            (p) => p["id"]?.toString() != recipientId,
          )
          .toList();
      if (nextProfiles.length == profiles.length &&
          nextIds.length == ids.length) {
        throw StateError(
          "That person was not found on this home document. Pull to refresh or check your care group link.",
        );
      }
      tx.update(ref, {
        "recipientIds": nextIds,
        "recipientProfiles": nextProfiles,
      });
    });
  }

  /// Pushes [displayName], [photoUrl], and [avatarIndex] from the user profile into every
  /// `careGroups/.../members/{uid}` row for this user so the members list can show
  /// [CareUserAvatar] without reading `users/{uid}` (other users' profiles are not readable).
  Future<void> syncMemberRosterFromProfile({
    required String uid,
    required UserProfile profile,
  }) async {
    if (!_firebaseReady) return;
    final snap = await FirebaseFirestore.instance
        .collectionGroup("members")
        .where(FieldPath.documentId, isEqualTo: uid)
        .get();
    if (snap.docs.isEmpty) return;

    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    for (final doc in snap.docs) {
      final patch = <String, dynamic>{
        "displayName": profile.displayName.trim(),
      };
      final pu = profile.photoUrl?.trim() ?? "";
      if (pu.isNotEmpty) {
        patch["photoUrl"] = pu;
        patch["avatarIndex"] = FieldValue.delete();
      } else {
        patch["photoUrl"] = FieldValue.delete();
        final ai = profile.avatarIndex;
        if (ai != null && ai >= 1) {
          patch["avatarIndex"] = ai;
        } else {
          patch["avatarIndex"] = FieldValue.delete();
        }
      }
      batch.update(doc.reference, patch);
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }
  }

  /// Updates `careGroups/{careGroupId}.name` (trimmed, non-empty).
  /// Firestore: [care_group_administrator] only for [name] patches.
  Future<void> updateCareGroupName({
    required String careGroupId,
    required String name,
  }) async {
    if (!_firebaseReady) return;
    final t = name.trim();
    if (t.isEmpty) {
      throw ArgumentError("Care group name cannot be empty.");
    }
    await FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .update({"name": t});
  }

  /// Merges [groupCalendar] sub-fields on **`careGroups/{careGroupDocId}`**.
  /// Firestore: [care_group_administrator] only for `groupCalendar` patches.
  Future<void> mergeCareGroupCalendar({
    required String careGroupDocId,
    String? calendarId,
    String? icalUrl,
    String? timezone,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final ref =
        FirebaseFirestore.instance.collection("careGroups").doc(careGroupDocId);
    final patch = <String, dynamic>{};
    void mergeField(String dotted, String? raw) {
      final t = raw?.trim();
      if (t == null || t.isEmpty) {
        patch[dotted] = FieldValue.delete();
      } else {
        patch[dotted] = t;
      }
    }

    mergeField("groupCalendar.calendarId", calendarId);
    mergeField("groupCalendar.icalUrl", icalUrl);
    mergeField("groupCalendar.timezone", timezone);

    await ref.update(patch);
  }

  /// Sets `careGroups/{careGroupId}.themeColor` (ARGB int). Firestore: administrator only.
  Future<void> setCareGroupThemeColor({
    required String careGroupId,
    int? argb,
  }) async {
    if (!_firebaseReady) return;
    final ref =
        FirebaseFirestore.instance.collection("careGroups").doc(careGroupId);
    if (argb == null) {
      await ref.update({"themeColor": FieldValue.delete()});
    } else {
      await ref.update({"themeColor": argb});
    }
  }

  /// Persists [UserProfile.activeCareGroupId] and removes a legacy extra field if present.
  Future<void> setActiveCareGroup({
    required String uid,
    required String careGroupId,
  }) async {
    if (!_firebaseReady) return;
    await _userRef(uid).update({
      "activeCareGroupId": careGroupId,
      firestoreUserLegacyActiveCareGroupField(): FieldValue.delete(),
    });
  }

  /// When [listCareGroupsForUser] is empty (e.g. collection-group) but the profile
  /// has [UserProfile.activeCareGroupId], build a [CareGroupOption] with direct [get]s.
  Future<CareGroupOption?> fetchCareGroupOptionForActiveProfile({
    required String uid,
    required String careGroupId,
  }) async {
    if (!_firebaseReady) return null;
    final teamRef =
        FirebaseFirestore.instance.collection("careGroups").doc(careGroupId);
    final teamSnap = await teamRef.get();
    if (!teamSnap.exists) return null;
    final data = teamSnap.data()!;
    final memberSnap = await teamRef.collection("members").doc(uid).get();
    if (!memberSnap.exists) return null;
    final mData = memberSnap.data() ?? {};
    final rawRoles = mData["roles"];
    final roles = rawRoles is List
        ? rawRoles.map((e) => e.toString()).toList()
        : <String>[];
    final linked = (data["careGroupId"] as String?)?.trim();
    final resolvedDataGroupId =
        (linked != null && linked.isNotEmpty) ? linked : careGroupId;
    var displayName = (data["name"] as String?)?.trim() ?? "";
    if (displayName.isEmpty) {
      String? hName;
      final h1 = await FirebaseFirestore.instance
          .collection(firestoreTopLevelHomeMetadataCollection())
          .doc(resolvedDataGroupId)
          .get();
      if (h1.exists) {
        hName = (h1.data()?["name"] as String?)?.trim();
        if (hName != null && hName.isEmpty) {
          hName = null;
        }
      }
      if (hName == null) {
        final h2 = await FirebaseFirestore.instance
            .collection("careGroups")
            .doc(resolvedDataGroupId)
            .get();
        if (h2.exists) {
          hName = (h2.data()?["name"] as String?)?.trim();
        }
      }
      displayName = (hName != null && hName.isNotEmpty) ? hName : "Care group";
    }
    return CareGroupOption(
      careGroupId: careGroupId,
      dataCareGroupId: resolvedDataGroupId,
      displayName: displayName,
      roles: roles,
      themeColor: _parseThemeColorArgb(data),
    );
  }

  /// Every care group where `careGroups/{id}/members/{uid}` exists; deduped by linked data
  /// document id, sorted by name.
  ///
  /// Uses a [collectionGroup] query on `members` and reads linked [careGroups] (and the
  /// top-level home metadata collection when present) for display names.
  Future<List<CareGroupOption>> listCareGroupsForUser(String uid) async {
    if (!_firebaseReady) return const [];

    final membersSnap = await FirebaseFirestore.instance
        .collectionGroup("members")
        .where(FieldPath.documentId, isEqualTo: uid)
        .get();

    if (membersSnap.docs.isEmpty) {
      return const [];
    }

    final byDataGroup = <String, CareGroupOption>{};

    for (final memberDoc in membersSnap.docs) {
      final mData = memberDoc.data();
      final rawRoles = mData["roles"];
      final roles = rawRoles is List
          ? rawRoles.map((e) => e.toString()).toList()
          : <String>[];
      final careGroupRef = memberDoc.reference.parent.parent;
      if (careGroupRef == null) continue;
      final careGroupDocId = careGroupRef.id;

      final cgSnap = await FirebaseFirestore.instance
          .collection("careGroups")
          .doc(careGroupDocId)
          .get();
      if (!cgSnap.exists) continue;
      final cgData = cgSnap.data()!;
      // Linked home: stored as `careGroupId` on the care group document (see setup wizard / rules).
      final linkedDataGroupId = cgData["careGroupId"] as String?;
      if (linkedDataGroupId == null || linkedDataGroupId.isEmpty) continue;
      if (byDataGroup.containsKey(linkedDataGroupId)) continue;

      final cgName = (cgData["name"] as String?)?.trim();
      String? hName;
      final hSnap = await FirebaseFirestore.instance
          .collection(firestoreTopLevelHomeMetadataCollection())
          .doc(linkedDataGroupId)
          .get();
      if (hSnap.exists) {
        hName = (hSnap.data()?["name"] as String?)?.trim();
        if (hName != null && hName.isEmpty) {
          hName = null;
        }
      }
      // Setup wizard may store the linked document only under [careGroups].
      String? fromCareGroupsHome;
      if (hName == null) {
        final hCg = await FirebaseFirestore.instance
            .collection("careGroups")
            .doc(linkedDataGroupId)
            .get();
        if (hCg.exists) {
          fromCareGroupsHome = (hCg.data()?["name"] as String?)?.trim();
          if (fromCareGroupsHome != null && fromCareGroupsHome.isEmpty) {
            fromCareGroupsHome = null;
          }
        }
      }
      final name = (cgName != null && cgName.isNotEmpty)
          ? cgName
          : (hName != null && hName.isNotEmpty)
              ? hName
              : (fromCareGroupsHome != null && fromCareGroupsHome.isNotEmpty)
                  ? fromCareGroupsHome
                  : "Care group";
      byDataGroup[linkedDataGroupId] = CareGroupOption(
        careGroupId: careGroupDocId,
        dataCareGroupId: linkedDataGroupId,
        displayName: name,
        roles: roles,
        themeColor: _parseThemeColorArgb(cgData),
      );
    }

    final list = byDataGroup.values.toList();
    list.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
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
      activeCareGroupId: data["activeCareGroupId"] as String?,
      wizardDraft: (data["wizardDraft"] as Map?)?.cast<String, dynamic>(),
    );
  }

  String _emailLocalPart(String email) {
    final at = email.indexOf("@");
    if (at <= 0) return "Carer";
    return email.substring(0, at);
  }

  static int? _parseThemeColorArgb(Map<String, dynamic> data) {
    final t = data["themeColor"];
    if (t is int) return t;
    if (t is num) return t.toInt();
    return null;
  }
}
