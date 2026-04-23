import "package:equatable/equatable.dart";

import "../models/care_group_member.dart";

sealed class MembersState extends Equatable {
  const MembersState();

  @override
  List<Object?> get props => [];
}

final class MembersInitial extends MembersState {
  const MembersInitial();
}

final class MembersLoading extends MembersState {
  const MembersLoading();
}

final class MembersEmpty extends MembersState {
  const MembersEmpty();
}

final class MembersDisplay extends MembersState {
  const MembersDisplay({required this.list});

  final List<CareGroupMember> list;

  @override
  List<Object?> get props => [list];
}

final class MembersFailure extends MembersState {
  const MembersFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
