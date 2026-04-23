import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/journal_entry.dart";

class JournalRepository {
  JournalRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _journal(String householdId) {
    return FirebaseFirestore.instance
        .collection("households")
        .doc(householdId)
        .collection("journalEntries");
  }

  Stream<List<JournalEntry>> watchJournal(String householdId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _journal(householdId)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map((s) => s.docs.map(JournalEntry.fromDoc).toList());
  }

  Future<void> addEntry({
    required String householdId,
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
    await _journal(householdId).add({
      "title": t,
      "body": body.trim(),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateEntry({
    required String householdId,
    required String entryId,
    required String title,
    String body = "",
  }) async {
    if (!_firebaseReady) return;
    await _journal(householdId).doc(entryId).update({
      "title": title.trim(),
      "body": body.trim(),
    });
  }

  Future<void> deleteEntry({
    required String householdId,
    required String entryId,
  }) async {
    if (!_firebaseReady) return;
    await _journal(householdId).doc(entryId).delete();
  }
}
