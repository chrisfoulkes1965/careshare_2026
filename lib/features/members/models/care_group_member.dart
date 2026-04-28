import "package:cloud_firestore/cloud_firestore.dart";
import "package:equatable/equatable.dart";

/// One document under [careGroups/{careGroupId}/members/{userId}].
final class CareGroupMember extends Equatable {
  const CareGroupMember({
    required this.userId,
    required this.displayName,
    required this.roles,
    this.joinedAt,
    this.kudosScore,
    this.photoUrl,
    this.avatarIndex,
    this.isOfflineOnly = false,
  });

  final String userId;
  final String displayName;
  final List<String> roles;
  final DateTime? joinedAt;
  final int? kudosScore;
  final String? photoUrl;
  /// Preset avatar (1-based), same as [UserProfile.avatarIndex] when not using [photoUrl].
  final int? avatarIndex;

  /// True when this row comes from [careGroups] `recipientProfiles` (no app account), not from `members/`.
  final bool isOfflineOnly;

  static CareGroupMember fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final rawRoles = d["roles"];
    final roles = rawRoles is List
        ? rawRoles.map((e) => e.toString()).toList()
        : <String>[];

    DateTime? joinedAt;
    final ja = d["joinedAt"];
    if (ja is Timestamp) {
      joinedAt = ja.toDate();
    }

    int? kudos;
    final k = d["kudosScore"];
    if (k is int) {
      kudos = k;
    } else if (k is num) {
      kudos = k.toInt();
    }

    int? av;
    final avRaw = d["avatarIndex"];
    if (avRaw is int) {
      av = avRaw;
    } else if (avRaw is num) {
      av = avRaw.toInt();
    }

    return CareGroupMember(
      userId: doc.id,
      displayName: (d["displayName"] as String?)?.trim() ?? "Member",
      roles: roles,
      joinedAt: joinedAt,
      kudosScore: kudos,
      photoUrl: d["photoUrl"] as String?,
      avatarIndex: av,
    );
  }

  bool get canAssignMemberRoles =>
      roles.contains("principal_carer") ||
      roles.contains("care_group_administrator");

  /// Matches Firestore [isCarerOrPrincipalForCareGroup] (includes care group administrator).
  bool get hasCarerOrOrganiserChatAccess =>
      roles.contains("principal_carer") ||
      roles.contains("carer") ||
      roles.contains("care_group_administrator");

  /// Person listed under [careGroups] `recipientProfiles` (e.g. [accessMode] `managed`).
  static CareGroupMember fromRecipientProfileMap(Map<String, dynamic> m) {
    final id = (m["id"] as String?)?.trim() ?? "";
    final name = (m["displayName"] as String?)?.trim() ?? "Recipient";
    return CareGroupMember(
      userId: id.isNotEmpty ? id : "unknown_recipient",
      displayName: name,
      roles: const ["receives_care"],
      isOfflineOnly: true,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        displayName,
        roles,
        joinedAt,
        kudosScore,
        photoUrl,
        avatarIndex,
        isOfflineOnly,
      ];
}
