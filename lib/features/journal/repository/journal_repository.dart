import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/journal_entry.dart";

class JournalRepository {
  JournalRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _journal(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("journalEntries");
  }

  Stream<List<JournalEntry>> watchJournal(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _journal(careGroupId)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map((s) => s.docs.map(JournalEntry.fromDoc).toList());
  }

  Future<void> addEntry({
    required String careGroupId,
    required String title,
    String body = "",
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
    await _journal(careGroupId).add({
      "title": t,
      "body": body.trim(),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateEntry({
    required String careGroupId,
    required String entryId,
    required String title,
    String body = "",
  }) async {
    if (!_firebaseReady) return;
    await _journal(careGroupId).doc(entryId).update({
      "title": title.trim(),
      "body": body.trim(),
    });
  }

  Future<void> deleteEntry({
    required String careGroupId,
    required String entryId,
  }) async {
    if (!_firebaseReady) return;
    await _journal(careGroupId).doc(entryId).delete();
  }
}
