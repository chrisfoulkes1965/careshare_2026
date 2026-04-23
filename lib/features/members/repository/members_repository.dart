import "package:cloud_firestore/cloud_firestore.dart";

import "../models/care_group_member.dart";

class MembersRepository {
  MembersRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _members(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("members");
  }

  /// Live list of everyone in the care group (read allowed for any group member per rules).
  Stream<List<CareGroupMember>> watchMembers(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _members(careGroupId).snapshots().map((s) => _sortMembers(s.docs.map(CareGroupMember.fromDoc).toList()));
  }

  /// One load for modals and pickers (e.g. task assignee).
  Future<List<CareGroupMember>> fetchMembers(String careGroupId) async {
    if (!_firebaseReady) return [];
    final snap = await _members(careGroupId).get();
    return _sortMembers(snap.docs.map(CareGroupMember.fromDoc).toList());
  }

  static List<CareGroupMember> _sortMembers(List<CareGroupMember> list) {
    list.sort((a, b) {
      final c = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      if (c != 0) return c;
      return a.userId.compareTo(b.userId);
    });
    return list;
  }
}
