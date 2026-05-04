import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:file_picker/file_picker.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../logic/medication_reminder_ack_id.dart";
import "../models/care_group_medication.dart";
import "../models/medication_batch_prep_doc.dart";
import "../models/medication_dose_log.dart";
import "../models/medication_reminder_ack.dart";
import "../models/medication_reminder_ack_draft.dart";
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

  CollectionReference<Map<String, dynamic>> _medicationReminderAcks(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("medicationReminderAcks");
  }

  DocumentReference<Map<String, dynamic>> _medicationBatchPrepDoc(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("medicationBatchPrep")
        .doc("current");
  }

  /// Monday date (YYYY-MM-DD) identifying the batch-prep week in local time.
  static String currentBatchPrepWeekKey(DateTime localNow) {
    final day = DateTime(localNow.year, localNow.month, localNow.day);
    final monday = day.subtract(Duration(days: (day.weekday + 6) % 7));
    return "${monday.year}-${monday.month.toString().padLeft(2, "0")}-${monday.day.toString().padLeft(2, "0")}";
  }

  Stream<MedicationBatchPrepDoc> watchMedicationBatchPrep(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _medicationBatchPrepDoc(careGroupId).snapshots().map(
      (s) {
        if (!s.exists || s.data() == null) {
          return MedicationBatchPrepDoc(
            weekKey: currentBatchPrepWeekKey(DateTime.now()),
            completedMedicationIds: const [],
          );
        }
        return MedicationBatchPrepDoc.fromMap(s.data()!);
      },
    );
  }

  Future<void> saveMedicationBatchPrep({
    required String careGroupId,
    required String weekKey,
    required List<String> completedMedicationIds,
  }) async {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final wk = weekKey.trim();
    if (wk.isEmpty) {
      throw ArgumentError("weekKey required.");
    }
    final unique = completedMedicationIds.where((e) => e.isNotEmpty).toSet().toList()..sort();
    return _withOpTimeout(
      _medicationBatchPrepDoc(careGroupId).set(
        {
          "weekKey": wk,
          "completedMedicationIds": unique,
          "updatedBy": uid,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    );
  }

  /// Ensures expectation docs exist for scheduled doses (merge-safe if already confirmed).
  Future<void> syncMedicationReminderAckExpectations({
    required String careGroupId,
    required List<MedicationReminderAckDraft> drafts,
  }) async {
    if (!_firebaseReady || drafts.isEmpty) {
      return;
    }
    await _withOpTimeout(
      FirebaseFirestore.instance.runTransaction((t) async {
        for (final d in drafts) {
          final ids = [...d.medicationIds]..sort();
          if (ids.isEmpty || d.slotKey.trim().isEmpty) {
            continue;
          }
          final docId = medicationReminderAckDocId(
            careGroupDataId: careGroupId,
            slotKey: d.slotKey.trim(),
            medicationIds: ids,
          );
          final ref = _medicationReminderAcks(careGroupId).doc(docId);
          final snap = await t.get(ref);
          final dueTs = Timestamp.fromDate(d.dueAtUtc);
          if (!snap.exists) {
            t.set(ref, {
              "slotKey": d.slotKey.trim(),
              "medicationIds": ids,
              "dueAt": dueTs,
              "needsConfirmation": true,
              "principalAlertSent": false,
              "updatedAt": FieldValue.serverTimestamp(),
            });
          } else {
            final data = snap.data();
            if (data != null && data["needsConfirmation"] == true) {
              t.update(ref, {
                "slotKey": d.slotKey.trim(),
                "medicationIds": ids,
                "dueAt": dueTs,
                "updatedAt": FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }),
    );
  }

  /// Pending confirmation acks (newest due first). Filter `dueAt <= now` in the UI so the list
  /// updates when time passes without requiring a new Firestore snapshot.
  Stream<List<MedicationReminderAck>> watchOverdueMedicationAcks(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _medicationReminderAcks(careGroupId)
        .where("needsConfirmation", isEqualTo: true)
        .orderBy("dueAt", descending: true)
        .limit(24)
        .snapshots()
        .map((s) => s.docs.map(MedicationReminderAck.fromDoc).toList());
  }

  Stream<List<MedicationDoseLogEntry>> watchRecentDoseLogs({
    required String careGroupId,
    required String medicationId,
    int limit = 25,
  }) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    final lim = limit.clamp(1, 100);
    return _medications(careGroupId)
        .doc(medicationId)
        .collection("doseLogs")
        .orderBy("takenAt", descending: true)
        .limit(lim)
        .snapshots()
        .map((s) => s.docs.map(MedicationDoseLogEntry.fromDoc).toList());
  }

  /// Carers may only patch [quantityOnHand] (and [lastStockDate]) on the medication document (see Firestore rules).
  Future<void> patchMedicationQuantityOnly({
    required String careGroupId,
    required String medicationId,
    required int quantityOnHand,
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    final q = quantityOnHand.clamp(0, 0x3fffffff);
    return _withOpTimeout(
      _medications(careGroupId).doc(medicationId).update({
        "quantityOnHand": q,
        "lastStockDate": FieldValue.serverTimestamp(),
      }),
    );
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
    required String careRecipientId,
    required String name,
    String medicationForm = "",
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    int? lowStockThreshold,
    PlatformFile? image,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    return _withOpTimeout(_addMedicationWork(
      careGroupId: careGroupId,
      careRecipientId: careRecipientId,
      name: name,
      medicationForm: medicationForm,
      dosage: dosage,
      instructions: instructions,
      notes: notes,
      reminderEnabled: reminderEnabled,
      reminderTimes: reminderTimes,
      scheduleType: scheduleType,
      scheduleWeekdays: scheduleWeekdays,
      scheduleMonthDays: scheduleMonthDays,
      quantityOnHand: quantityOnHand,
      lowStockThreshold: lowStockThreshold,
      image: image,
      alsoApplyPhotoToMedicationIds: alsoApplyPhotoToMedicationIds,
    ));
  }

  Future<void> _addMedicationWork({
    required String careGroupId,
    required String careRecipientId,
    required String name,
    String medicationForm = "",
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    int? lowStockThreshold,
    PlatformFile? image,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final cr = careRecipientId.trim();
    if (cr.isEmpty) {
      throw ArgumentError("Choose who this medication is for.");
    }
    final t = name.trim();
    if (t.isEmpty) {
      throw ArgumentError("Medication name is required.");
    }
    final data = <String, dynamic>{
      "careRecipientId": cr.length > 128 ? cr.substring(0, 128) : cr,
      "name": t,
      "medicationForm": medicationForm.trim(),
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
      data["lastStockDate"] = FieldValue.serverTimestamp();
    }
    if (lowStockThreshold != null) {
      data["lowStockThreshold"] = lowStockThreshold.clamp(0, 0x3fffffff);
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
    required String careRecipientId,
    required String name,
    String medicationForm = "",
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    int? lowStockThreshold,
    bool clearQuantity = false,
    bool clearLowStock = false,
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
      careRecipientId: careRecipientId,
      name: name,
      medicationForm: medicationForm,
      dosage: dosage,
      instructions: instructions,
      notes: notes,
      reminderEnabled: reminderEnabled,
      reminderTimes: reminderTimes,
      scheduleType: scheduleType,
      scheduleWeekdays: scheduleWeekdays,
      scheduleMonthDays: scheduleMonthDays,
      quantityOnHand: quantityOnHand,
      lowStockThreshold: lowStockThreshold,
      clearQuantity: clearQuantity,
      clearLowStock: clearLowStock,
      clearPhoto: clearPhoto,
      newImage: newImage,
      alsoApplyPhotoToMedicationIds: alsoApplyPhotoToMedicationIds,
    ));
  }

  Future<void> _updateMedicationWork({
    required String careGroupId,
    required String medicationId,
    required String careRecipientId,
    required String name,
    String medicationForm = "",
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    int? lowStockThreshold,
    bool clearQuantity = false,
    bool clearLowStock = false,
    bool clearPhoto = false,
    PlatformFile? newImage,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) async {
    final cr = careRecipientId.trim();
    if (cr.isEmpty) {
      throw ArgumentError("Choose who this medication is for.");
    }
    final t = name.trim();
    if (t.isEmpty) {
      throw ArgumentError("Medication name is required.");
    }
    final patch = <String, dynamic>{
      "careRecipientId": cr.length > 128 ? cr.substring(0, 128) : cr,
      "name": t,
      "medicationForm": medicationForm.trim(),
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
      patch["lastStockDate"] = FieldValue.serverTimestamp();
    } else if (quantityOnHand != null) {
      patch["quantityOnHand"] = quantityOnHand.clamp(0, 0x3fffffff);
      patch["lastStockDate"] = FieldValue.serverTimestamp();
    }
    if (clearLowStock) {
      patch["lowStockThreshold"] = FieldValue.delete();
    } else if (lowStockThreshold != null) {
      patch["lowStockThreshold"] = lowStockThreshold.clamp(0, 0x3fffffff);
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

  /// Bulk stock-take: per medication, write the user-entered count or clear it
  /// (back to the implicit 28-day estimate) when the entry is `null`.
  /// Entries with no change versus current state should be omitted by callers
  /// to keep the batch small.
  Future<void> applyStockTake({
    required String careGroupId,
    required Map<String, int?> entries,
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    if (entries.isEmpty) {
      return Future.value();
    }
    return _withOpTimeout(_applyStockTakeWork(
      careGroupId: careGroupId,
      entries: entries,
    ));
  }

  Future<void> _applyStockTakeWork({
    required String careGroupId,
    required Map<String, int?> entries,
  }) async {
    final ids = entries.keys.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) {
      return;
    }
    const chunk = 400;
    for (var i = 0; i < ids.length; i += chunk) {
      final batch = FirebaseFirestore.instance.batch();
      final slice = ids.sublist(
        i,
        i + chunk > ids.length ? ids.length : i + chunk,
      );
      for (final id in slice) {
        final v = entries[id];
        final ref = _medications(careGroupId).doc(id);
        if (v == null) {
          batch.update(ref, {
            "quantityOnHand": FieldValue.delete(),
            "lastStockDate": FieldValue.serverTimestamp(),
          });
        } else {
          batch.update(ref, {
            "quantityOnHand": v.clamp(0, 0x3fffffff),
            "lastStockDate": FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    }
  }

  /// When a scheduled dose is due, reduces on-hand counts once per reminder ack (even if nobody confirms).
  Future<void> applyScheduledDoseInventoryForOverdueAcks(String careGroupId) {
    if (!_firebaseReady) {
      return Future.value();
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future.value();
    }
    final now = DateTime.now();
    return _withOpTimeout(_applyScheduledDoseInventoryForOverdueAcksWork(
      careGroupId: careGroupId,
      uid: uid,
      now: now,
    ));
  }

  Future<void> _applyScheduledDoseInventoryForOverdueAcksWork({
    required String careGroupId,
    required String uid,
    required DateTime now,
  }) async {
    final snap = await _medicationReminderAcks(careGroupId)
        .where("needsConfirmation", isEqualTo: true)
        .orderBy("dueAt", descending: true)
        .limit(48)
        .get();
    for (final doc in snap.docs) {
      final ack = MedicationReminderAck.fromDoc(doc);
      if (ack.dueAt == null || ack.dueAt!.isAfter(now)) {
        continue;
      }
      if (ack.inventoryAdjustedAt != null) {
        continue;
      }
      try {
        await FirebaseFirestore.instance.runTransaction((t) async {
          final ackRef = doc.reference;
          final ackSnap = await t.get(ackRef);
          if (!ackSnap.exists || ackSnap.data() == null) {
            return;
          }
          final data = ackSnap.data()!;
          if (data["needsConfirmation"] != true) {
            return;
          }
          if (data["inventoryAdjustedAt"] != null) {
            return;
          }
          final dueRaw = data["dueAt"];
          DateTime? dueAt;
          if (dueRaw is Timestamp) {
            dueAt = dueRaw.toDate();
          }
          if (dueAt == null || dueAt.isAfter(now)) {
            return;
          }
          final slotKey = (data["slotKey"] as String?)?.trim() ?? "";
          final ids = _medicationIdsFromAckMap(data);
          for (final id in ids) {
            await _decrementMedicationStockForDose(
              t,
              careGroupId: careGroupId,
              medicationId: id,
              uid: uid,
              trimmedSlot: slotKey,
              scheduledDeduction: true,
            );
          }
          t.update(ackRef, {
            "inventoryAdjustedAt": FieldValue.serverTimestamp(),
            "inventoryAdjustedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
          });
        });
      } catch (_) {}
    }
  }

  List<String> _medicationIdsFromAckMap(Map<String, dynamic> data) {
    final rawIds = data["medicationIds"];
    final ids = <String>[];
    if (rawIds is List) {
      for (final e in rawIds) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) {
          ids.add(s);
        }
      }
    }
    ids.sort();
    return ids;
  }

  Future<void> _decrementMedicationStockForDose(
    Transaction t, {
    required String careGroupId,
    required String medicationId,
    required String uid,
    required String trimmedSlot,
    required bool scheduledDeduction,
  }) async {
    if (medicationId.isEmpty) {
      return;
    }
    final r = _medications(careGroupId).doc(medicationId);
    final s = await t.get(r);
    if (!s.exists || s.data() == null) {
      return;
    }
    final m = CareGroupMedication.fromMap(medicationId, s.data()!);
    if (!m.reminderEnabled || m.reminderTimes.isEmpty) {
      return;
    }
    if (!m.hasValidReminderSchedule) {
      return;
    }
    final start = m.effectiveDosesInHand;
    final next = (start - 1).clamp(0, 0x3fffffff);
    final logRef = r.collection("doseLogs").doc();
    final logData = <String, dynamic>{
      "takenAt": FieldValue.serverTimestamp(),
      "loggedBy": uid,
    };
    if (trimmedSlot.isNotEmpty) {
      logData["slotKey"] = trimmedSlot.length > 120 ? trimmedSlot.substring(0, 120) : trimmedSlot;
    }
    if (scheduledDeduction) {
      logData["scheduledDeduction"] = true;
    }
    t.set(logRef, logData);
    t.update(r, {
      "quantityOnHand": next,
      "lastStockDate": FieldValue.serverTimestamp(),
    });
  }

  /// One dose from each listed medication: writes a [doseLogs] entry and decrements stock by 1,
  /// unless stock was already reduced when the dose became due ([inventoryAdjustedAt] on the ack).
  Future<void> applyDoseDecrements({
    required String careGroupId,
    required Set<String> medicationIds,
    String slotKey = "",
  }) {
    if (!_firebaseReady) {
      return Future.error(StateError("Firebase is not available."));
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future.error(StateError("Not signed in."));
    }
    final trimmedSlot = slotKey.trim();
    final sortedIds = medicationIds.where((e) => e.isNotEmpty).toList()..sort();
    final ackDocId = trimmedSlot.isNotEmpty && sortedIds.isNotEmpty
        ? medicationReminderAckDocId(
            careGroupDataId: careGroupId,
            slotKey: trimmedSlot,
            medicationIds: sortedIds,
          )
        : null;
    return _withOpTimeout(
      FirebaseFirestore.instance.runTransaction((t) async {
        if (ackDocId != null) {
          final ackRef = _medicationReminderAcks(careGroupId).doc(ackDocId);
          final ackSnap = await t.get(ackRef);
          if (ackSnap.exists && ackSnap.data() != null && ackSnap.data()!["inventoryAdjustedAt"] != null) {
            t.update(ackRef, {
              "needsConfirmation": false,
              "acknowledgedAt": FieldValue.serverTimestamp(),
              "acknowledgedBy": uid,
              "updatedAt": FieldValue.serverTimestamp(),
            });
            return;
          }
        }
        for (final id in medicationIds) {
          if (id.isEmpty) {
            continue;
          }
          await _decrementMedicationStockForDose(
            t,
            careGroupId: careGroupId,
            medicationId: id,
            uid: uid,
            trimmedSlot: trimmedSlot,
            scheduledDeduction: false,
          );
        }
        if (ackDocId != null) {
          final ackRef = _medicationReminderAcks(careGroupId).doc(ackDocId);
          final ackSnap2 = await t.get(ackRef);
          if (ackSnap2.exists) {
            t.update(ackRef, {
              "needsConfirmation": false,
              "acknowledgedAt": FieldValue.serverTimestamp(),
              "acknowledgedBy": uid,
              "updatedAt": FieldValue.serverTimestamp(),
            });
          }
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
