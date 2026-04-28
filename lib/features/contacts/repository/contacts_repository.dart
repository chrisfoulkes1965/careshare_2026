import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/care_group_contact.dart";

class ContactsRepository {
  ContactsRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _contacts(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("contacts");
  }

  Stream<List<CareGroupContact>> watchContacts(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _contacts(careGroupId)
        .orderBy("name")
        .snapshots()
        .map((s) => s.docs.map(CareGroupContact.fromDoc).toList());
  }

  Future<void> addContact({
    required String careGroupId,
    required String name,
    String phone = "",
    String email = "",
    String notes = "",
  }) async {
    if (!_firebaseReady) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final n = name.trim();
    if (n.isEmpty) {
      throw ArgumentError("Name is required.");
    }
    await _contacts(careGroupId).add({
      "name": n,
      "phone": phone.trim(),
      "email": email.trim(),
      "notes": notes.trim(),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateContact({
    required String careGroupId,
    required String contactId,
    required String name,
    String phone = "",
    String email = "",
    String notes = "",
  }) async {
    if (!_firebaseReady) return;
    await _contacts(careGroupId).doc(contactId).update({
      "name": name.trim(),
      "phone": phone.trim(),
      "email": email.trim(),
      "notes": notes.trim(),
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteContact({
    required String careGroupId,
    required String contactId,
  }) async {
    if (!_firebaseReady) return;
    await _contacts(careGroupId).doc(contactId).delete();
  }
}
