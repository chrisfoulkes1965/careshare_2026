import "package:cloud_firestore/cloud_firestore.dart";
import "package:file_picker/file_picker.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../models/household_medication.dart";
import "../../tasks/repository/platform_file_read_io.dart" if (dart.library.html) "../../tasks/repository/platform_file_read_web.dart" as platform_file_read;

class MedicationsRepository {
  MedicationsRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  static const int _maxBytes = 8 * 1024 * 1024;

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _medications(String householdId) {
    return FirebaseFirestore.instance
        .collection("households")
        .doc(householdId)
        .collection("medications");
  }

  Stream<List<HouseholdMedication>> watchMedications(String householdId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _medications(householdId).snapshots().map(
          (s) {
            final list = s.docs.map(HouseholdMedication.fromDoc).toList();
            list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return list;
          },
        );
  }

  String _safeFileName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
    if (n.isEmpty) n = "photo";
    return n.length > 200 ? n.substring(0, 200) : n;
  }

  Future<String> _uploadPhotoIfAny({
    required String householdId,
    required String medicationId,
    PlatformFile? file,
  }) async {
    if (file == null) {
      return "";
    }
    final bytes = await platform_file_read.readPlatformFileBytes(file);
    if (bytes == null || bytes.isEmpty) {
      return "";
    }
    if (bytes.length > _maxBytes) {
      throw ArgumentError("Image must be 8 MB or smaller.");
    }
    final name = _safeFileName(file.name);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref()
        .child("households/$householdId/medication_photos/$medicationId/${stamp}_$name");
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<void> addMedication({
    required String householdId,
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    PlatformFile? image,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final t = name.trim();
    if (t.isEmpty) {
      throw ArgumentError("Medication name is required.");
    }
    final data = <String, dynamic>{
      "name": t,
      "dosage": dosage.trim(),
      "instructions": instructions.trim(),
      "notes": notes.trim(),
      "reminderEnabled": reminderEnabled,
      "reminderTimes": reminderTimes.map((e) => e.toMap()).toList(),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    };
    final ref = await _medications(householdId).add(data);
    final id = ref.id;
    if (image != null) {
      final url = await _uploadPhotoIfAny(
        householdId: householdId,
        medicationId: id,
        file: image,
      );
      if (url.isNotEmpty) {
        await ref.update({"photoUrl": url});
      } else {
        await ref.update({"photoUrl": FieldValue.delete()});
      }
    }
  }

  Future<void> updateMedication({
    required String householdId,
    required String medicationId,
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    bool clearPhoto = false,
    PlatformFile? newImage,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final t = name.trim();
    if (t.isEmpty) {
      throw ArgumentError("Medication name is required.");
    }
    final patch = <String, dynamic>{
      "name": t,
      "dosage": dosage.trim(),
      "instructions": instructions.trim(),
      "notes": notes.trim(),
      "reminderEnabled": reminderEnabled,
      "reminderTimes": reminderTimes.map((e) => e.toMap()).toList(),
    };
    if (clearPhoto) {
      patch["photoUrl"] = FieldValue.delete();
    }
    await _medications(householdId).doc(medicationId).update(patch);
    if (newImage != null) {
      final url = await _uploadPhotoIfAny(
        householdId: householdId,
        medicationId: medicationId,
        file: newImage,
      );
      if (url.isNotEmpty) {
        await _medications(householdId).doc(medicationId).update({"photoUrl": url});
      }
    }
  }

  Future<void> deleteMedication({
    required String householdId,
    required String medicationId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    await _medications(householdId).doc(medicationId).delete();
  }
}
