import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/care_group_note.dart";

class NotesRepository {
  NotesRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _notes(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("notes");
  }

  Stream<List<CareGroupNote>> watchNotes(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _notes(careGroupId)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map((s) => s.docs.map(CareGroupNote.fromDoc).toList());
  }

  Future<void> addNote({
    required String careGroupId,
    required String title,
    required String type,
    String body = "",
    String? legalCategory,
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
    final data = <String, dynamic>{
      "title": t,
      "type": type,
      "body": body.trim(),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    };
    if (legalCategory == "legal") {
      data["category"] = "legal";
    }
    await _notes(careGroupId).add(data);
  }

  Future<void> updateNote({
    required String careGroupId,
    required String noteId,
    required String title,
    required String type,
    required String body,
    String? legalCategory,
  }) async {
    if (!_firebaseReady) return;
    final data = <String, dynamic>{
      "title": title.trim(),
      "type": type,
      "body": body.trim(),
    };
    if (legalCategory == "legal") {
      data["category"] = "legal";
    } else {
      data["category"] = FieldValue.delete();
    }
    await _notes(careGroupId).doc(noteId).update(data);
  }

  Future<void> deleteNote({
    required String careGroupId,
    required String noteId,
  }) async {
    if (!_firebaseReady) return;
    await _notes(careGroupId).doc(noteId).delete();
  }
}
