import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../core/medication_reminders/medication_notification_service.dart";
import "../models/care_group_medication.dart";
import "../repository/medications_repository.dart";
import "medications_state.dart";

final class MedicationsCubit extends Cubit<MedicationsState> {
  MedicationsCubit({
    required MedicationsRepository repository,
    required this.careGroupId,
  })  : _repository = repository,
        super(const MedicationsInitial());

  final MedicationsRepository _repository;
  final String careGroupId;

  StreamSubscription<List<CareGroupMedication>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const MedicationsFailure("Firebase is not available."));
      return;
    }
    emit(const MedicationsLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchMedications(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const MedicationsEmpty());
        } else {
          emit(MedicationsDisplay(list: list));
        }
        // Defer: local notification sync can block the platform channel on some OSes; never run in the
        // same turn as the Firestore write that produced this snapshot.
        Future(
          () => MedicationNotificationService.instance.syncMedications(careGroupId, list),
        );
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
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    PlatformFile? image,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) {
    return _repository.addMedication(
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
    MedicationScheduleType scheduleType = MedicationScheduleType.daily,
    List<int> scheduleWeekdays = const [],
    List<int> scheduleMonthDays = const [],
    int? quantityOnHand,
    bool clearQuantity = false,
    bool clearPhoto = false,
    PlatformFile? newImage,
    List<String> alsoApplyPhotoToMedicationIds = const [],
  }) {
    return _repository.updateMedication(
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
    );
  }

  Future<void> deleteMedication(String medicationId) {
    return _repository.deleteMedication(
      careGroupId: careGroupId,
      medicationId: medicationId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
