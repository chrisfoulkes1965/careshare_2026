import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/care_group_meeting.dart";

class MeetingsRepository {
  MeetingsRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _meetings(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("meetings");
  }

  Stream<List<CareGroupMeeting>> watchMeetings(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _meetings(careGroupId)
        .orderBy("meetingAt", descending: true)
        .snapshots()
        .map((s) => s.docs.map(CareGroupMeeting.fromDoc).toList());
  }

  Future<void> addMeeting({
    required String careGroupId,
    required String title,
    String body = "",
    String location = "",
    required DateTime meetingAt,
  }) async {
    if (!_firebaseReady) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final t = title.trim();
    if (t.isEmpty) {
      throw ArgumentError("Title is required.");
    }
    await _meetings(careGroupId).add({
      "title": t,
      "body": body.trim(),
      "location": location.trim(),
      "meetingAt": Timestamp.fromDate(meetingAt),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMeeting({
    required String careGroupId,
    required String meetingId,
    required String title,
    String body = "",
    String location = "",
    required DateTime meetingAt,
  }) async {
    if (!_firebaseReady) return;
    await _meetings(careGroupId).doc(meetingId).update({
      "title": title.trim(),
      "body": body.trim(),
      "location": location.trim(),
      "meetingAt": Timestamp.fromDate(meetingAt),
    });
  }

  Future<void> deleteMeeting({
    required String careGroupId,
    required String meetingId,
  }) async {
    if (!_firebaseReady) return;
    await _meetings(careGroupId).doc(meetingId).delete();
  }
}
