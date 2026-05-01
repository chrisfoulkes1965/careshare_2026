import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../core/medication_reminders/medication_notification_service.dart";
import "../models/care_group_medication.dart";
import "../models/medication_care_group_settings.dart";
import "../repository/medication_care_group_settings_repository.dart";
import "../repository/medications_repository.dart";
import "medications_state.dart";

final class MedicationsCubit extends Cubit<MedicationsState> {
  MedicationsCubit({
    required MedicationsRepository repository,
    required MedicationCareGroupSettingsRepository settingsRepository,
    required this.careGroupId,
  })  : _repository = repository,
        _settingsRepository = settingsRepository,
        super(const MedicationsInitial());

  final MedicationsRepository _repository;
  final MedicationCareGroupSettingsRepository _settingsRepository;
  final String careGroupId;

  StreamSubscription<List<CareGroupMedication>>? _sub;
  StreamSubscription<MedicationInventoryCareGroupSettings>? _settingsSub;
  List<CareGroupMedication> _lastMedsForNotify = const [];

  Future<void> _syncLocalNotifications() async {
    if (!_repository.isAvailable) {
      return;
    }
    final settings = await _settingsRepository.getSettings(careGroupId);
    await MedicationNotificationService.instance.syncMedications(
      careGroupId,
      _lastMedsForNotify,
      quietHoursStartMinute: settings.quietHoursEnabled ? settings.quietHoursStartMinute : null,
      quietHoursEndMinute: settings.quietHoursEnabled ? settings.quietHoursEndMinute : null,
    );
  }

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const MedicationsFailure("Firebase is not available."));
      return;
    }
    emit(const MedicationsLoading());
    unawaited(_sub?.cancel());
    unawaited(_settingsSub?.cancel());
    _settingsSub = _settingsRepository.watchSettings(careGroupId).listen(
      (_) {
        Future(_syncLocalNotifications);
      },
    );
    _sub = _repository.watchMedications(careGroupId).listen(
      (list) {
        _lastMedsForNotify = list;
        if (list.isEmpty) {
          emit(const MedicationsEmpty());
        } else {
          emit(MedicationsDisplay(list: list));
        }
        Future(_syncLocalNotifications);
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
    int? lowStockThreshold,
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
      lowStockThreshold: lowStockThreshold,
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
    int? lowStockThreshold,
    bool clearQuantity = false,
    bool clearLowStock = false,
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
      lowStockThreshold: lowStockThreshold,
      clearQuantity: clearQuantity,
      clearLowStock: clearLowStock,
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

  /// Batch update doses-on-hand from a stock take. Use `null` in [entries] to
  /// clear an entry back to the implicit 28-day estimate.
  Future<void> applyStockTake(Map<String, int?> entries) {
    return _repository.applyStockTake(
      careGroupId: careGroupId,
      entries: entries,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _settingsSub?.cancel();
    return super.close();
  }
}
