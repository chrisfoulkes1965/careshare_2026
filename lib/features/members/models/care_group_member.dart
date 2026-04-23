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
  });

  final String userId;
  final String displayName;
  final List<String> roles;
  final DateTime? joinedAt;
  final int? kudosScore;
  final String? photoUrl;

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

    return CareGroupMember(
      userId: doc.id,
      displayName: (d["displayName"] as String?)?.trim() ?? "Member",
      roles: roles,
      joinedAt: joinedAt,
      kudosScore: kudos,
      photoUrl: d["photoUrl"] as String?,
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
      ];
}
