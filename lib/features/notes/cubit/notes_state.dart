import "package:equatable/equatable.dart";

import "../models/care_group_note.dart";

sealed class NotesState extends Equatable {
  const NotesState();

  @override
  List<Object?> get props => [];
}

final class NotesInitial extends NotesState {
  const NotesInitial();
}

final class NotesLoading extends NotesState {
  const NotesLoading();
}

final class NotesEmpty extends NotesState {
  const NotesEmpty();
}

final class NotesDisplay extends NotesState {
  const NotesDisplay({required this.list});

  final List<CareGroupNote> list;

  @override
  List<Object?> get props => [list];
}

final class NotesFailure extends NotesState {
  const NotesFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
