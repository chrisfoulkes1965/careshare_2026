import "package:cloud_firestore/cloud_firestore.dart";

import "../models/medication_care_group_settings.dart";

class MedicationCareGroupSettingsRepository {
  MedicationCareGroupSettingsRepository({required bool firebaseReady}) : _ok = firebaseReady;

  final bool _ok;

  DocumentReference<Map<String, dynamic>> _householdRef(String householdId) =>
      FirebaseFirestore.instance.collection("careGroups").doc(householdId);

  Stream<MedicationInventoryCareGroupSettings> watchSettings(String householdId) {
    if (!_ok) {
      return Stream.value(const MedicationInventoryCareGroupSettings());
    }
    return _householdRef(householdId).snapshots().map(
          (s) => MedicationInventoryCareGroupSettings.fromData(s.data()),
        );
  }

  Future<MedicationInventoryCareGroupSettings> getSettings(String householdId) async {
    if (!_ok) {
      return const MedicationInventoryCareGroupSettings();
    }
    final s = await _householdRef(householdId).get();
    return MedicationInventoryCareGroupSettings.fromData(s.data());
  }

  Future<void> saveSettings(
    String householdId,
    MedicationInventoryCareGroupSettings s,
  ) async {
    if (!_ok) {
      return;
    }
    await _householdRef(householdId).set(s.toMap(), SetOptions(merge: true));
  }
}
