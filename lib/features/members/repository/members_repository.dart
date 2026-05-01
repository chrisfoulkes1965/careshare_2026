import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";

import "../models/care_group_member.dart";
import "../models/member_deletion_blockers.dart";

class MembersRepository {
  MembersRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  static const String _careGroupAdministratorRole = "care_group_administrator";

  final bool _firebaseReady;

  static bool _rolesListContainsAdministrator(List<String> roles) {
    return roles.contains(_careGroupAdministratorRole);
  }

  static List<String> _rolesFromMemberData(Map<String, dynamic> data) {
    final raw = data["roles"];
    if (raw is! List) {
      return const [];
    }
    return raw.map((e) => e.toString()).toList();
  }

  /// Returns how many members would have [care_group_administrator] after updating [userId]’s roles.
  static int _administratorCountAfterRoleChange({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs,
    required String userId,
    required List<String> newRolesForUser,
  }) {
    var n = 0;
    for (final d in memberDocs) {
      final roles =
          d.id == userId ? newRolesForUser : _rolesFromMemberData(d.data());
      if (_rolesListContainsAdministrator(roles)) {
        n++;
      }
    }
    return n;
  }

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

  /// Signed-in members from [members/] plus people in [dataCareGroupDocId]’s
  /// [recipientProfiles] who do not use the app, so the roster updates as soon
  /// as [UserRepository.addOfflineCareRecipient] runs.
  Stream<List<CareGroupMember>> watchRoster(
    String careGroupId,
    String dataCareGroupDocId,
  ) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    final firestore = FirebaseFirestore.instance;
    var lastM = <CareGroupMember>[];
    var lastO = <CareGroupMember>[];
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub1;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub2;
    late final StreamController<List<CareGroupMember>> controller;

    void emit() {
      if (!controller.isClosed) {
        controller.add(_mergeRoster(lastM, lastO));
      }
    }

    controller = StreamController<List<CareGroupMember>>(
      onListen: () {
        sub1 = _members(careGroupId).snapshots().listen(
          (s) {
            lastM = s.docs.map(CareGroupMember.fromDoc).toList();
            emit();
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) {
              controller.addError(e, st);
            }
          },
        );
        sub2 = firestore
            .collection("careGroups")
            .doc(dataCareGroupDocId)
            .snapshots()
            .listen(
          (s) {
            lastO = _offlineRecipientsFromHomeDocument(s);
            emit();
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) {
              controller.addError(e, st);
            }
          },
        );
      },
      onCancel: () async {
        await sub1?.cancel();
        await sub2?.cancel();
      },
    );
    return controller.stream;
  }

  static List<CareGroupMember> _offlineRecipientsFromHomeDocument(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (!snap.exists) {
      return const [];
    }
    final data = snap.data() ?? {};
    final raw = data["recipientProfiles"];
    if (raw is! List) {
      return const [];
    }
    final byId = <String, CareGroupMember>{};
    for (final e in raw) {
      if (e is! Map) {
        continue;
      }
      final o = CareGroupMember.fromRecipientProfileMap(
        Map<String, dynamic>.from(e),
      );
      if (o.userId.isEmpty) {
        continue;
      }
      byId[o.userId] = o;
    }
    return byId.values.toList();
  }

  /// Uses [watchRoster] when [dataCareGroupDocId] is set; otherwise [watchMembers] only.
  Stream<List<CareGroupMember>> watchMembersOrRoster(
    String careGroupId,
    String? dataCareGroupDocId,
  ) {
    if (dataCareGroupDocId != null && dataCareGroupDocId.isNotEmpty) {
      return watchRoster(careGroupId, dataCareGroupDocId);
    }
    return watchMembers(careGroupId);
  }

  static List<CareGroupMember> _mergeRoster(
    List<CareGroupMember> members,
    List<CareGroupMember> offline,
  ) {
    final nameLower = {
      for (final m in members) m.displayName.toLowerCase().trim(),
    };
    final add = <CareGroupMember>[];
    for (final o in offline) {
      if (!o.isOfflineOnly) {
        continue;
      }
      final n = o.displayName.toLowerCase().trim();
      if (n.isNotEmpty && nameLower.contains(n)) {
        continue;
      }
      add.add(o);
    }
    return _sortMembers([...members, ...add]);
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

  /// Replaces the member’s role list. Principal carer can update any member; others cannot.
  ///
  /// Every care group must keep at least one [care_group_administrator].
  Future<void> updateMemberRoles({
    required String careGroupId,
    required String userId,
    required List<String> roles,
  }) async {
    if (!_firebaseReady) return;
    final unique = <String>{...roles}.toList()..sort();
    final snap = await _members(careGroupId).get();
    final adminsAfter = _administratorCountAfterRoleChange(
      memberDocs: snap.docs,
      userId: userId,
      newRolesForUser: unique,
    );
    if (adminsAfter < 1) {
      throw StateError(
        "This care team must have at least one care group administrator.",
      );
    }
    await _members(careGroupId).doc(userId).update({"roles": unique});
  }

  /// Whether this roster id can be removed: no tasks, notes, journal, or chat channel ties.
  ///
  /// “Offline” recipient ids (`rcp_…`) are never Firebase uids, so we only need to check
  /// [tasks] for [assignedTo] — other collections use uids and would throw or need indexes
  /// pointlessly. Signed-in members get the full set of checks.
  Future<MemberDeletionBlockers> getDeletionBlockers({
    required String dataCareGroupId,
    required String entityId,
  }) async {
    if (!_firebaseReady) {
      return const MemberDeletionBlockers();
    }
    if (dataCareGroupId.isEmpty || entityId.isEmpty) {
      return const MemberDeletionBlockers();
    }
    final root = FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataCareGroupId);

    final isOfflineRosterId = entityId.startsWith("rcp_");

    if (isOfflineRosterId) {
      final snap = await root
          .collection("tasks")
          .where("assignedTo", isEqualTo: entityId)
          .limit(1)
          .get();
      return MemberDeletionBlockers(
        hasTaskAssignment: snap.docs.isNotEmpty,
      );
    }

    final results = await Future.wait([
      root
          .collection("tasks")
          .where("assignedTo", isEqualTo: entityId)
          .limit(1)
          .get(),
      root
          .collection("notes")
          .where("createdBy", isEqualTo: entityId)
          .limit(1)
          .get(),
      root
          .collection("journalEntries")
          .where("createdBy", isEqualTo: entityId)
          .limit(1)
          .get(),
      root
          .collection("chatChannels")
          .where("memberUids", arrayContains: entityId)
          .limit(1)
          .get(),
      root
          .collection("expenses")
          .where("createdBy", isEqualTo: entityId)
          .limit(1)
          .get(),
    ]);
    return MemberDeletionBlockers(
      hasTaskAssignment: results[0].docs.isNotEmpty,
      hasAuthoredNote: results[1].docs.isNotEmpty,
      hasAuthoredJournal: results[2].docs.isNotEmpty,
      isInChatChannel: results[3].docs.isNotEmpty,
      hasExpenses: results[4].docs.isNotEmpty,
    );
  }

  /// Principal-only; fails if [userId] is not in `members/`. Use [UserRepository] to remove
  /// “offline” rows from [recipientProfiles].
  ///
  /// Removing a member must leave at least one [care_group_administrator] on the team.
  Future<void> deleteMemberDocument({
    required String careGroupId,
    required String userId,
  }) async {
    if (!_firebaseReady) return;
    final snap = await _members(careGroupId).get();
    var adminsRemaining = 0;
    for (final d in snap.docs) {
      if (d.id == userId) {
        continue;
      }
      if (_rolesListContainsAdministrator(_rolesFromMemberData(d.data()))) {
        adminsRemaining++;
      }
    }
    if (adminsRemaining < 1) {
      throw StateError(
        "This care team must have at least one care group administrator. "
        "Promote someone else before removing this person.",
      );
    }
    await _members(careGroupId).doc(userId).delete();
  }
}
