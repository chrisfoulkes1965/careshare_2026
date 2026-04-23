import "package:equatable/equatable.dart";

import "../models/journal_entry.dart";

sealed class JournalState extends Equatable {
  const JournalState();

  @override
  List<Object?> get props => [];
}

final class JournalInitial extends JournalState {
  const JournalInitial();
}

final class JournalLoading extends JournalState {
  const JournalLoading();
}

final class JournalEmpty extends JournalState {
  const JournalEmpty();
}

final class JournalDisplay extends JournalState {
  const JournalDisplay({required this.list});

  final List<JournalEntry> list;

  @override
  List<Object?> get props => [list];
}

/// User is signed in as "receives care only" (or otherwise blocked by rules).
final class JournalForbidden extends JournalState {
  const JournalForbidden();
}

final class JournalFailure extends JournalState {
  const JournalFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
