import "package:equatable/equatable.dart";

import "../models/care_invitation.dart";

sealed class InvitationsState extends Equatable {
  const InvitationsState();

  @override
  List<Object?> get props => [];
}

final class InvitationsInitial extends InvitationsState {
  const InvitationsInitial();
}

final class InvitationsLoading extends InvitationsState {
  const InvitationsLoading();
}

final class InvitationsEmpty extends InvitationsState {
  const InvitationsEmpty();
}

final class InvitationsDisplay extends InvitationsState {
  const InvitationsDisplay({required this.list});

  final List<CareInvitation> list;

  @override
  List<Object?> get props => [list];
}

final class InvitationsFailure extends InvitationsState {
  const InvitationsFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
