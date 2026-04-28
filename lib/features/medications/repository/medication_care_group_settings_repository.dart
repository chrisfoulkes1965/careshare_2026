import "package:cloud_firestore/cloud_firestore.dart";

import "../models/medication_care_group_settings.dart";

class MedicationCareGroupSettingsRepository {
  MedicationCareGroupSettingsRepository({required bool firebaseReady}) : _ok = firebaseReady;

  final bool _ok;

  DocumentReference<Map<String, dynamic>> _careGroupDocRef(String careGroupId) =>
      FirebaseFirestore.instance.collection("careGroups").doc(careGroupId);

  Stream<MedicationInventoryCareGroupSettings> watchSettings(String careGroupId) {
    if (!_ok) {
      return Stream.value(const MedicationInventoryCareGroupSettings());
    }
    return _careGroupDocRef(careGroupId).snapshots().map(
          (s) => MedicationInventoryCareGroupSettings.fromData(s.data()),
        );
  }

  Future<MedicationInventoryCareGroupSettings> getSettings(String careGroupId) async {
    if (!_ok) {
      return const MedicationInventoryCareGroupSettings();
    }
    final s = await _careGroupDocRef(careGroupId).get();
    return MedicationInventoryCareGroupSettings.fromData(s.data());
  }

  Future<void> saveSettings(
    String careGroupId,
    MedicationInventoryCareGroupSettings s,
  ) async {
    if (!_ok) {
      return;
    }
    await _careGroupDocRef(careGroupId).set(s.toMap(), SetOptions(merge: true));
  }
}
