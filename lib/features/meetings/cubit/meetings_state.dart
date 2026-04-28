import "package:equatable/equatable.dart";

import "../models/care_group_meeting.dart";

sealed class MeetingsState extends Equatable {
  const MeetingsState();

  @override
  List<Object?> get props => [];
}

final class MeetingsInitial extends MeetingsState {
  const MeetingsInitial();
}

final class MeetingsLoading extends MeetingsState {
  const MeetingsLoading();
}

final class MeetingsEmpty extends MeetingsState {
  const MeetingsEmpty();
}

final class MeetingsDisplay extends MeetingsState {
  const MeetingsDisplay({required this.list});

  final List<CareGroupMeeting> list;

  @override
  List<Object?> get props => [list];
}

final class MeetingsForbidden extends MeetingsState {
  const MeetingsForbidden();
}

final class MeetingsFailure extends MeetingsState {
  const MeetingsFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
