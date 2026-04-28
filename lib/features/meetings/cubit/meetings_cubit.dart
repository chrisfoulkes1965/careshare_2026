import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../models/care_group_meeting.dart";
import "../repository/meetings_repository.dart";
import "meetings_state.dart";

final class MeetingsCubit extends Cubit<MeetingsState> {
  MeetingsCubit({
    required MeetingsRepository repository,
    required this.careGroupId,
  })  : _repository = repository,
        super(const MeetingsInitial());

  final MeetingsRepository _repository;
  final String careGroupId;

  StreamSubscription<List<CareGroupMeeting>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const MeetingsFailure("Firebase is not available."));
      return;
    }
    emit(const MeetingsLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchMeetings(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const MeetingsEmpty());
        } else {
          emit(MeetingsDisplay(list: list));
        }
      },
      onError: (Object e) {
        final s = e.toString();
        if (s.contains("permission-denied") || s.contains("PERMISSION_DENIED")) {
          emit(const MeetingsForbidden());
        } else {
          emit(MeetingsFailure(s));
        }
      },
    );
  }

  Future<void> addMeeting({
    required String title,
    String body = "",
    String location = "",
    required DateTime meetingAt,
  }) {
    return _repository.addMeeting(
      careGroupId: careGroupId,
      title: title,
      body: body,
      location: location,
      meetingAt: meetingAt,
    );
  }

  Future<void> updateMeeting({
    required String meetingId,
    required String title,
    String body = "",
    String location = "",
    required DateTime meetingAt,
  }) {
    return _repository.updateMeeting(
      careGroupId: careGroupId,
      meetingId: meetingId,
      title: title,
      body: body,
      location: location,
      meetingAt: meetingAt,
    );
  }

  Future<void> deleteMeeting(String meetingId) {
    return _repository.deleteMeeting(
      careGroupId: careGroupId,
      meetingId: meetingId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
