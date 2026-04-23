import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/household_contact.dart";

class ContactsRepository {
  ContactsRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _contacts(String householdId) {
    return FirebaseFirestore.instance
        .collection("households")
        .doc(householdId)
        .collection("contacts");
  }

  Stream<List<HouseholdContact>> watchContacts(String householdId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _contacts(householdId)
        .orderBy("name")
        .snapshots()
        .map((s) => s.docs.map(HouseholdContact.fromDoc).toList());
  }

  Future<void> addContact({
    required String householdId,
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
    await _contacts(householdId).add({
      "name": n,
      "phone": phone.trim(),
      "email": email.trim(),
      "notes": notes.trim(),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateContact({
    required String householdId,
    required String contactId,
    required String name,
    String phone = "",
    String email = "",
    String notes = "",
  }) async {
    if (!_firebaseReady) return;
    await _contacts(householdId).doc(contactId).update({
      "name": name.trim(),
      "phone": phone.trim(),
      "email": email.trim(),
      "notes": notes.trim(),
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteContact({
    required String householdId,
    required String contactId,
  }) async {
    if (!_firebaseReady) return;
    await _contacts(householdId).doc(contactId).delete();
  }
}
