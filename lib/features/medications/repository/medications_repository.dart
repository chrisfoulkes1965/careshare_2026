import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:file_picker/file_picker.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../models/care_group_medication.dart";
import "../../tasks/repository/platform_file_read_io.dart" if (dart.library.html) "../../tasks/repository/platform_file_read_web.dart" as platform_file_read;

Map<String, dynamic> _scheduleFields({
  required MedicationScheduleType scheduleType,
  required List<int> scheduleWeekdays,
  required List<int> scheduleMonthDays,
}) {
  return {
    "reminderSchedule": scheduleType.name,
    "reminderWeekdays": scheduleWeekdays,
    "reminderMonthDays": scheduleMonthDays,
  };
}

class MedicationsRepository {
  MedicationsRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  static const int _maxBytes = 8 * 1024 * 1024;
  static const Duration _opTimeout = Duration(minutes: 2);

  bool get isAvailable => _firebaseReady;

  Future<T> _withOpTimeout<T>(Future<T> f) {
    return f.timeout(
      _opTimeout,
      onTimeout: () {
        throw TimeoutException(
          "This is taking too long. Check your network, try again without a photo, or use a smaller image.",
        );
      },
    );
  }

  CollectionReference<Map<String, dynamic>> _medications(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("medications");
  }

  Stream<List<CareGroupMedication>> watchMedications(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _medications(careGroupId).snapshots().map(
          (s) {
            final list = s.docs.map(CareGroupMedication.fromDoc).toList();
            list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return list;
          },
        );
  }

  Future<List<CareGroupMedication>> fetchMedicationsByIds({
    required String careGroupId,
    required List<String> medicationIds,
  }) async {
    if (!_firebaseReady) {
      return const [];
    }
    final out = <CareGroupMedication>[];
    for (final id in medicationIds) {
      final s = await _medications(careGroupId).doc(id).get();
      if (s.exists && s.data() != null) {
        out.add(CareGroupMedication.fromMap(s.id, s.data()!));
      }
    }
    return out;
  }

  String _safeFileName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
    if (n.isEmpty) n = "photo";
    return n.length > 200 ? n.substring(0, 200) : n;
  }

  /// Reuses the same [photoUrl] on other medication docs (one upload, many references).
  Future<void> _applyPhotoUrlToMedications({
    required String careGroupId,
    required String photoUrl,
    required List<String> medicationIds,
  }) async {
    final unique = medicationIds.toSet().toList();
    if (unique.isEmpty) {
      return;
    }
    const chunk = 400;
    for (var i = 0; i < unique.length; i += chunk) {
      final batch = FirebaseFirestore.instance.batch();
      final slice = unique.sublist(
        i,
        i + chunk > unique.length ? unique.length : i + chunk,
      );
      for (final id in slice) {
        batch.update(
          _medications(careGroupId).doc(id),
          {"photoUrl": photoUrl},
        );
      }
      await batch.commit();
    }
  }

  Future<String> _uploadPhotoIfAny({
    required String careGroupId,
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
        .child("careGroups/$careGroupId/medication_photos/$medicationId/${stamp}_$name");
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<void> addMedication({
    required String careGroupId,
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    PlatformFile? image,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    return _withOpTimeout(_addMedicationWork(
      careGroupId: careGroupId,
      name: name,
      dosage: dosage,
      instructions: instructions,
      notes: notes,
      reminderEnabled: reminderEnabled,
      reminderTimes: reminderTimes,
      scheduleType: scheduleType,
      scheduleWeekdays: scheduleWeekdays,
      scheduleMonthDays: scheduleMonthDays,
      quantityOnHand: quantityOnHand,
      image: image,
      alsoApplyPhotoToMedicationIds: alsoApplyPhotoToMedicationIds,
    ));
  }

  Future<void> _addMedicationWork({
    required String careGroupId,
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    PlatformFile? image,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) async {
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
      ..._scheduleFields(
        scheduleType: scheduleType,
        scheduleWeekdays: scheduleWeekdays,
        scheduleMonthDays: scheduleMonthDays,
      ),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    };
    if (quantityOnHand != null) {
      data["quantityOnHand"] = quantityOnHand.clamp(0, 0x3fffffff);
    }
    final ref = await _medications(careGroupId).add(data);
    final id = ref.id;
    if (image != null) {
      final url = await _uploadPhotoIfAny(
        careGroupId: careGroupId,
        medicationId: id,
        file: image,
      );
      if (url.isNotEmpty) {
        await ref.update({"photoUrl": url});
        final others = alsoApplyPhotoToMedicationIds
            .where((oid) => oid.isNotEmpty && oid != id)
            .toSet()
            .toList();
        if (others.isNotEmpty) {
          await _applyPhotoUrlToMedications(
            careGroupId: careGroupId,
            photoUrl: url,
            medicationIds: others,
          );
        }
      } else {
        await ref.update({"photoUrl": FieldValue.delete()});
      }
    }
  }

  Future<void> updateMedication({
    required String careGroupId,
    required String medicationId,
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    bool clearQuantity = false,
    bool clearPhoto = false,
    PlatformFile? newImage,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    return _withOpTimeout(_updateMedicationWork(
      careGroupId: careGroupId,
      medicationId: medicationId,
      name: name,
      dosage: dosage,
      instructions: instructions,
      notes: notes,
      reminderEnabled: reminderEnabled,
      reminderTimes: reminderTimes,
      scheduleType: scheduleType,
      scheduleWeekdays: scheduleWeekdays,
      scheduleMonthDays: scheduleMonthDays,
      quantityOnHand: quantityOnHand,
      clearQuantity: clearQuantity,
      clearPhoto: clearPhoto,
      newImage: newImage,
      alsoApplyPhotoToMedicationIds: alsoApplyPhotoToMedicationIds,
    ));
  }

  Future<void> _updateMedicationWork({
    required String careGroupId,
    required String medicationId,
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    bool clearQuantity = false,
    bool clearPhoto = false,
    PlatformFile? newImage,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) async {
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
      ..._scheduleFields(
        scheduleType: scheduleType,
        scheduleWeekdays: scheduleWeekdays,
        scheduleMonthDays: scheduleMonthDays,
      ),
    };
    if (clearPhoto) {
      patch["photoUrl"] = FieldValue.delete();
    }
    if (clearQuantity) {
      patch["quantityOnHand"] = FieldValue.delete();
    } else if (quantityOnHand != null) {
      patch["quantityOnHand"] = quantityOnHand.clamp(0, 0x3fffffff);
    }
    await _medications(careGroupId).doc(medicationId).update(patch);
    if (newImage != null) {
      final url = await _uploadPhotoIfAny(
        careGroupId: careGroupId,
        medicationId: medicationId,
        file: newImage,
      );
      if (url.isNotEmpty) {
        await _medications(careGroupId).doc(medicationId).update({"photoUrl": url});
        final others = alsoApplyPhotoToMedicationIds
            .where((oid) => oid.isNotEmpty && oid != medicationId)
            .toSet()
            .toList();
        if (others.isNotEmpty) {
          await _applyPhotoUrlToMedications(
            careGroupId: careGroupId,
            photoUrl: url,
            medicationIds: others,
          );
        }
      }
    }
  }

  /// One dose from each listed medication: decrements by 1, materializing implicit 28d stock.
  Future<void> applyDoseDecrements({
    required String careGroupId,
    required Set<String> medicationIds,
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    return _withOpTimeout(
      FirebaseFirestore.instance.runTransaction((t) async {
        for (final id in medicationIds) {
          final r = _medications(careGroupId).doc(id);
          final s = await t.get(r);
          if (!s.exists) {
            continue;
          }
          final m = CareGroupMedication.fromMap(id, s.data()!);
          if (!m.reminderEnabled || m.reminderTimes.isEmpty) {
            continue;
          }
          if (!m.hasValidReminderSchedule) {
            continue;
          }
          final start = m.effectiveDosesInHand;
          final next = (start - 1).clamp(0, 0x3fffffff);
          t.update(r, {"quantityOnHand": next});
        }
      }),
    );
  }

  Future<void> deleteMedication({
    required String careGroupId,
    required String medicationId,
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    return _withOpTimeout(
      _medications(careGroupId).doc(medicationId).delete(),
    );
  }
}
