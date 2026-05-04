import "dart:typed_data";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../../../core/firebase/firestore_remote_compat.dart";
import "../../care_group/models/care_group_option.dart";
import "../models/alternate_email.dart";
import "../models/alternate_phone.dart";
import "../models/home_sections_visibility.dart";
import "../models/expense_payment_details.dart";
import "../models/postal_address.dart";
import "../models/user_alert_preferences.dart";
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

  Future<void> ensureUserDocument(UserProfile identity) async {
    if (!_firebaseReady) return;
    final ref = _userRef(identity.uid);
    final snap = await ref.get();
    if (snap.exists) return;

    final email = identity.email;
    final displayName = identity.displayName.trim().isNotEmpty
        ? identity.displayName.trim()
        : _emailLocalPart(email);

    await ref.set(
      {
        "displayName": displayName,
        "email": email,
        "photoUrl": identity.photoUrl,
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

  /// IANA timezone id (e.g. `Europe/London`) for server-side medication push mirrors.
  Future<void> syncMedicationRemindersTimezone({
    required String uid,
    required String timezone,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final t = timezone.trim();
    if (t.isEmpty || t.length > 120) {
      return;
    }
    await _userRef(uid).set(
      {"medicationRemindersTimezone": t},
      SetOptions(merge: true),
    );
  }

  /// Replaces the address sub-map on `users/{uid}` (or removes it when
  /// [address] is `null` / empty).
  Future<void> setPostalAddress(String uid, PostalAddress? address) async {
    if (!_firebaseReady) return;
    if (address == null || address.isEmpty) {
      await _userRef(uid).update({"address": FieldValue.delete()});
      return;
    }
    await _userRef(uid).update({"address": address.toFirestore()});
  }

  /// Sets primary [phone] (or clears it when null/empty).
  Future<void> setPrimaryPhone(String uid, String? phone) async {
    if (!_firebaseReady) return;
    final t = phone?.trim() ?? "";
    await _userRef(uid).update({
      "phone": t.isEmpty ? FieldValue.delete() : t,
    });
  }

  /// Sets [fullName] (or clears it when null/empty).
  Future<void> setFullName(String uid, String? fullName) async {
    if (!_firebaseReady) return;
    final t = fullName?.trim() ?? "";
    await _userRef(uid).update({
      "fullName": t.isEmpty ? FieldValue.delete() : t,
    });
  }

  /// Persists the alternate-phones list on `users/{uid}.alternatePhones`.
  /// Pass `[]` to clear; the repo serialises each entry through
  /// [AlternatePhone.toFirestore] so server timestamps and label keys are
  /// dropped when empty.
  Future<void> setAlternatePhones(
    String uid,
    List<AlternatePhone> phones,
  ) async {
    if (!_firebaseReady) return;
    final out = phones
        .where((p) => p.normalized.isNotEmpty)
        .map((p) => p.toFirestore())
        .toList();
    await _userRef(uid).update({"alternatePhones": out});
  }

  /// Persists the alternate-emails list on `users/{uid}.alternateEmails`.
  /// Pass `[]` to clear. The Cloud Function `confirmAlternateEmailVerification`
  /// is the canonical writer for [AlternateEmail.verified] = true; clients should
  /// only call this method to add / remove / re-trigger entries.
  Future<void> setAlternateEmails(
    String uid,
    List<AlternateEmail> emails,
  ) async {
    if (!_firebaseReady) return;
    final out = emails
        .where((e) => e.normalized.isNotEmpty)
        .map((e) => e.toFirestore())
        .toList();
    await _userRef(uid).update({"alternateEmails": out});
  }

  /// Asks the `sendAlternateEmailVerification` Cloud Function to email a one-time
  /// verification link to [emailAddress]. Throws on permission / config errors.
  Future<void> requestAlternateEmailVerification({
    required String emailAddress,
  }) async {
    if (!_firebaseReady) return;
    final fn = FirebaseFunctions.instanceFor(region: "us-central1")
        .httpsCallable("sendAlternateEmailVerification");
    await fn.call({"email": emailAddress.trim().toLowerCase()});
  }

  /// Resolves a verification token (from the email link) into a verified
  /// alt-email entry on the calling user's profile. Returns the address that
  /// was verified, or throws on invalid / expired tokens.
  Future<String> confirmAlternateEmailVerification({
    required String token,
  }) async {
    if (!_firebaseReady) {
      throw StateError("Firebase is not ready.");
    }
    final fn = FirebaseFunctions.instanceFor(region: "us-central1")
        .httpsCallable("confirmAlternateEmailVerification");
    final res = await fn.call({"token": token});
    final data = res.data;
    if (data is Map) {
      final addr = data["email"];
      if (addr is String && addr.isNotEmpty) {
        return addr;
      }
    }
    return "";
  }

  Future<void> setHomeSectionsVisibility({
    required String uid,
    required HomeSectionsVisibility visibility,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    await _userRef(uid).update({
      "homeSections": visibility.toFirestoreUpdate(),
    });
  }

  /// Writes `careGroups/{dataCareGroupDocId}.homepageSectionsPolicy` (administrator only).
  Future<void> setCareGroupHomepageSectionsPolicy({
    required String dataCareGroupDocId,
    required HomeSectionsVisibility policy,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    await FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataCareGroupDocId)
        .set(
          {"homepageSectionsPolicy": policy.toGroupPolicyFirestoreMap()},
          SetOptions(merge: true),
        );
  }

  /// Removes group-wide homepage caps so members only follow their own preferences.
  Future<void> clearCareGroupHomepageSectionsPolicy(
    String dataCareGroupDocId,
  ) async {
    if (!_firebaseReady) {
      return;
    }
    await FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataCareGroupDocId)
        .update({"homepageSectionsPolicy": FieldValue.delete()});
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

  static const int _profilePhotoMaxBytes = 8 * 1024 * 1024;

  /// Uploads raw image bytes to Storage at `users/{uid}/profile_photo/…` and returns the download URL.
  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (!_firebaseReady) {
      throw StateError("Firebase is not ready.");
    }
    if (bytes.isEmpty) {
      throw ArgumentError("Choose an image file.");
    }
    if (bytes.length > _profilePhotoMaxBytes) {
      throw ArgumentError("Photo must be 8 MB or smaller.");
    }
    final mt = mimeType?.toLowerCase().trim() ?? "";
    String ext = "jpg";
    String contentType = "image/jpeg";
    if (mt.contains("png")) {
      ext = "png";
      contentType = "image/png";
    } else if (mt.contains("webp")) {
      ext = "webp";
      contentType = "image/webp";
    } else if (mt.contains("gif")) {
      ext = "gif";
      contentType = "image/gif";
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref()
        .child("users/$uid/profile_photo/${stamp}_photo.$ext");
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
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

  static const int _careGroupAvatarMaxBytes = 8 * 1024 * 1024;

  /// Uploads to Storage and sets `careGroups/{dataCareGroupDocId}.photoUrl`.
  ///
  /// [storageCareGroupDocId] is the `careGroups` document id used in the Storage path
  /// (typically [CareGroupOption.careGroupId] where `members/{uid}` lives). It may differ
  /// from [dataCareGroupDocId] when a shell doc links to shared data (must match Storage rules).
  /// Firestore: [care_group_administrator] only (see rules).
  Future<void> uploadAndSetCareGroupAvatarPhoto({
    required String dataCareGroupDocId,
    required String storageCareGroupDocId,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (!_firebaseReady) {
      throw StateError("Firebase is not configured.");
    }
    if (bytes.isEmpty) {
      throw ArgumentError("Choose an image file.");
    }
    if (bytes.length > _careGroupAvatarMaxBytes) {
      throw ArgumentError("Photo must be 8 MB or smaller.");
    }
    final mt = mimeType?.toLowerCase().trim() ?? "";
    String ext = "jpg";
    String contentType = "image/jpeg";
    if (mt.contains("png")) {
      ext = "png";
      contentType = "image/png";
    } else if (mt.contains("webp")) {
      ext = "webp";
      contentType = "image/webp";
    } else if (mt.contains("gif")) {
      ext = "gif";
      contentType = "image/gif";
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef = FirebaseStorage.instance
        .ref()
        .child("careGroups/$storageCareGroupDocId/group_avatar/${stamp}_avatar.$ext");
    await storageRef.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await storageRef.getDownloadURL();
    await FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataCareGroupDocId)
        .update({"photoUrl": url.trim()});
  }

  /// Clears `careGroups/{dataCareGroupDocId}.photoUrl` and best-effort deletes the prior Storage object.
  Future<void> clearCareGroupAvatarPhoto(String dataCareGroupDocId) async {
    if (!_firebaseReady) return;
    final ref = FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataCareGroupDocId);
    final snap = await ref.get();
    final prev = (snap.data()?["photoUrl"] as String?)?.trim();
    await ref.update({"photoUrl": FieldValue.delete()});
    if (prev != null &&
        prev.isNotEmpty &&
        prev.startsWith("http") &&
        prev.contains("firebasestorage")) {
      try {
        await FirebaseStorage.instance.refFromURL(prev).delete();
      } catch (_) {}
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

  /// Clears [UserProfile.activeCareGroupId] when it points at a team the user
  /// does not belong to (orphaned profile state).
  Future<void> clearActiveCareGroup(String uid) async {
    if (!_firebaseReady) return;
    await _userRef(uid).update({
      "activeCareGroupId": FieldValue.delete(),
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
    Map<String, dynamic> policyHost = data;
    if (resolvedDataGroupId != careGroupId) {
      final policySnap = await FirebaseFirestore.instance
          .collection("careGroups")
          .doc(resolvedDataGroupId)
          .get();
      policyHost = policySnap.data() ?? {};
    }
    final homepagePolicy =
        HomeSectionsVisibility.homepageGroupPolicyFromFirestore(
      policyHost["homepageSectionsPolicy"],
    );
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
      homepageSectionsPolicy: homepagePolicy,
      photoUrl: _parseOptionalImageUrl(policyHost["photoUrl"]),
    );
  }

  /// Every care group where `careGroups/{id}/members/{uid}` exists.
  ///
  /// Multiple `members/` rows may point at the same shared data document (team shells
  /// referencing `careGroupId` → merged home); we keep one option per **[resolved Data
  /// doc]**, matching [CareGroupOption.dataCareGroupId] / [mergeCareGroupCalendar] /
  /// [LinkedCalendarEventsRepository.watchLinkedEvents].
  ///
  /// When several rows resolve to the same data id, prefer the row whose
  /// [careGroups] document id equals that id (canonical merged doc) over a shell —
  /// so [profile.activeCareGroupId] aligns with calendar/tasks data paths consistently.
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

    final byResolvedData = <String, CareGroupOption>{};
    final policyHostCache = <String, Map<String, dynamic>>{};

    Future<Map<String, dynamic>> policyHostFor({
      required String resolvedDataGroupId,
      required String careGroupDocId,
      required Map<String, dynamic> careGroupData,
    }) async {
      if (resolvedDataGroupId == careGroupDocId) {
        return careGroupData;
      }
      final cached = policyHostCache[resolvedDataGroupId];
      if (cached != null) {
        return cached;
      }
      final snap = await FirebaseFirestore.instance
          .collection("careGroups")
          .doc(resolvedDataGroupId)
          .get();
      final m = snap.data() ?? <String, dynamic>{};
      policyHostCache[resolvedDataGroupId] = m;
      return m;
    }

    CareGroupOption pickPreferCanonical(
      CareGroupOption prior,
      CareGroupOption incoming,
      String resolved,
    ) {
      final canonPrior = prior.careGroupId == resolved;
      final canonInc = incoming.careGroupId == resolved;
      if (canonInc && !canonPrior) {
        return incoming;
      }
      if (canonPrior && !canonInc) {
        return prior;
      }
      return prior;
    }

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
      final rawLinked = cgData["careGroupId"];
      final linkedTrim = rawLinked is String
          ? rawLinked.trim()
          : (rawLinked != null ? rawLinked.toString().trim() : "");
      final resolvedDataGroupId =
          linkedTrim.isNotEmpty ? linkedTrim : careGroupDocId;

      final cgName = (cgData["name"] as String?)?.trim();
      String? hName;
      final hSnap = await FirebaseFirestore.instance
          .collection(firestoreTopLevelHomeMetadataCollection())
          .doc(resolvedDataGroupId)
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
            .doc(resolvedDataGroupId)
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
      final policyHost = await policyHostFor(
        resolvedDataGroupId: resolvedDataGroupId,
        careGroupDocId: careGroupDocId,
        careGroupData: cgData,
      );
      final homepagePolicy =
          HomeSectionsVisibility.homepageGroupPolicyFromFirestore(
        policyHost["homepageSectionsPolicy"],
      );
      final incoming = CareGroupOption(
        careGroupId: careGroupDocId,
        dataCareGroupId: resolvedDataGroupId,
        displayName: name,
        roles: roles,
        themeColor: _parseThemeColorArgb(cgData),
        homepageSectionsPolicy: homepagePolicy,
        photoUrl: _parseOptionalImageUrl(policyHost["photoUrl"]),
      );

      final prior = byResolvedData[resolvedDataGroupId];
      if (prior == null) {
        byResolvedData[resolvedDataGroupId] = incoming;
      } else {
        byResolvedData[resolvedDataGroupId] =
            pickPreferCanonical(prior, incoming, resolvedDataGroupId);
      }
    }

    final list = byResolvedData.values.toList();
    list.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return list;
  }

  UserProfile _map(String uid, Map<String, dynamic> data) {
    final altEmails = <AlternateEmail>[];
    final rawAltEmails = data["alternateEmails"];
    if (rawAltEmails is List) {
      for (final raw in rawAltEmails) {
        final e = AlternateEmail.fromFirestore(raw);
        if (e != null) {
          altEmails.add(e);
        }
      }
    }
    final altPhones = <AlternatePhone>[];
    final rawAltPhones = data["alternatePhones"];
    if (rawAltPhones is List) {
      for (final raw in rawAltPhones) {
        final p = AlternatePhone.fromFirestore(raw);
        if (p != null) {
          altPhones.add(p);
        }
      }
    }
    return UserProfile(
      uid: uid,
      email: (data["email"] as String?) ?? "",
      displayName: (data["displayName"] as String?) ?? "",
      fullName: (data["fullName"] as String?)?.trim().isNotEmpty == true
          ? (data["fullName"] as String).trim()
          : null,
      phone: (data["phone"] as String?)?.trim().isNotEmpty == true
          ? (data["phone"] as String).trim()
          : null,
      address: PostalAddress.fromFirestore(data["address"]),
      alternateEmails: altEmails,
      alternatePhones: altPhones,
      photoUrl: data["photoUrl"] as String?,
      avatarIndex: (data["avatarIndex"] as num?)?.toInt(),
      simpleMode: data["simpleMode"] as bool? ?? false,
      wizardCompleted: data["wizardCompleted"] as bool? ?? false,
      wizardSkipped: data["wizardSkipped"] as bool? ?? false,
      activeCareGroupId: data["activeCareGroupId"] as String?,
      wizardDraft: (data["wizardDraft"] as Map?)?.cast<String, dynamic>(),
      homeSections:
          HomeSectionsVisibility.fromFirestoreMap(data["homeSections"]),
      alertPreferences:
          UserAlertPreferences.fromFirestore(data["alertPreferences"]),
      expensePaymentDetails:
          ExpensePaymentDetails.fromFirestore(data["expensePaymentDetails"]),
    );
  }

  /// Persists `users/{uid}.expensePaymentDetails` for reimbursements (or removes it).
  Future<void> setExpensePaymentDetails(
    String uid,
    ExpensePaymentDetails? details,
  ) async {
    if (!_firebaseReady) {
      return;
    }
    if (details == null) {
      await _userRef(uid).update({
        "expensePaymentDetails": FieldValue.delete(),
      });
      return;
    }
    if (!details.isComplete) {
      throw ArgumentError("Expense payment details are incomplete.");
    }
    await _userRef(uid).update({
      "expensePaymentDetails": details.toFirestore(),
    });
  }

  /// Persists `users/{uid}.alertPreferences` (merge).
  Future<void> setAlertPreferences({
    required String uid,
    required UserAlertPreferences preferences,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    await _userRef(uid).set(
      {"alertPreferences": preferences.toMap()},
      SetOptions(merge: true),
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

  static String? _parseOptionalImageUrl(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
