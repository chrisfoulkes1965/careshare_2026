import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../core/medication_reminders/medication_notification_service.dart";
import "../models/household_medication.dart";
import "../repository/medications_repository.dart";
import "medications_state.dart";

final class MedicationsCubit extends Cubit<MedicationsState> {
  MedicationsCubit({
    required MedicationsRepository repository,
    required this.householdId,
  })  : _repository = repository,
        super(const MedicationsInitial());

  final MedicationsRepository _repository;
  final String householdId;

  StreamSubscription<List<HouseholdMedication>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const MedicationsFailure("Firebase is not available."));
      return;
    }
    emit(const MedicationsLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchMedications(householdId).listen(
      (list) {
        unawaited(MedicationNotificationService.instance.syncMedications(householdId, list));
        if (list.isEmpty) {
          emit(const MedicationsEmpty());
        } else {
          emit(MedicationsDisplay(list: list));
        }
      },
      onError: (Object e) => emit(MedicationsFailure(e.toString())),
    );
  }

  Future<void> addMedication({
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    PlatformFile? image,
  }) {
    return _repository.addMedication(
      householdId: householdId,
      name: name,
      dosage: dosage,
      instructions: instructions,
      notes: notes,
      reminderEnabled: reminderEnabled,
      reminderTimes: reminderTimes,
      image: image,
    );
  }

  Future<void> updateMedication({
    required String medicationId,
    required String name,
    String dosage = "",
    String instructions = "",
    String notes = "",
    bool reminderEnabled = false,
    List<MedicationReminderTime> reminderTimes = const [],
    bool clearPhoto = false,
    PlatformFile? newImage,
  }) {
    return _repository.updateMedication(
      householdId: householdId,
      medicationId: medicationId,
      name: name,
      dosage: dosage,
      instructions: instructions,
      notes: notes,
      reminderEnabled: reminderEnabled,
      reminderTimes: reminderTimes,
      clearPhoto: clearPhoto,
      newImage: newImage,
    );
  }

  Future<void> deleteMedication(String medicationId) {
    return _repository.deleteMedication(
      householdId: householdId,
      medicationId: medicationId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
