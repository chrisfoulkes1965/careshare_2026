import "package:equatable/equatable.dart";

import "../models/household_contact.dart";

sealed class ContactsState extends Equatable {
  const ContactsState();

  @override
  List<Object?> get props => [];
}

final class ContactsInitial extends ContactsState {
  const ContactsInitial();
}

final class ContactsLoading extends ContactsState {
  const ContactsLoading();
}

final class ContactsEmpty extends ContactsState {
  const ContactsEmpty();
}

final class ContactsDisplay extends ContactsState {
  const ContactsDisplay({required this.list});

  final List<CareGroupContact> list;

  @override
  List<Object?> get props => [list];
}

final class ContactsFailure extends ContactsState {
  const ContactsFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
