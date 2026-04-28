import "package:cloud_firestore/cloud_firestore.dart";

import "../models/linked_calendar_event.dart";

class LinkedCalendarEventsRepository {
  LinkedCalendarEventsRepository({required bool firebaseReady}) : _ok = firebaseReady;

  final bool _ok;

  bool get isAvailable => _ok;

  CollectionReference<Map<String, dynamic>> _col(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("linkedCalendarEvents");
  }

  Stream<List<LinkedCalendarEvent>> watchLinkedEvents(String careGroupId) {
    if (!_ok) {
      return const Stream.empty();
    }
    return _col(careGroupId)
        .orderBy("startAt", descending: true)
        .snapshots()
        .map((s) => s.docs.map(LinkedCalendarEvent.fromDoc).toList());
  }
}
