import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../models/journal_entry.dart";
import "../repository/journal_repository.dart";
import "journal_state.dart";

final class JournalCubit extends Cubit<JournalState> {
  JournalCubit({
    required JournalRepository repository,
    required this.careGroupId,
  })  : _repository = repository,
        super(const JournalInitial());

  final JournalRepository _repository;
  final String careGroupId;

  StreamSubscription<List<JournalEntry>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const JournalFailure("Firebase is not available."));
      return;
    }
    emit(const JournalLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchJournal(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const JournalEmpty());
        } else {
          emit(JournalDisplay(list: list));
        }
      },
      onError: (Object e) {
        final s = e.toString();
        if (s.contains("permission-denied") || s.contains("PERMISSION_DENIED")) {
          emit(const JournalForbidden());
        } else {
          emit(JournalFailure(s));
        }
      },
    );
  }

  Future<void> addEntry({required String title, String body = ""}) {
    return _repository.addEntry(careGroupId: careGroupId, title: title, body: body);
  }

  Future<void> updateEntry({
    required String entryId,
    required String title,
    String body = "",
  }) {
    return _repository.updateEntry(
      careGroupId: careGroupId,
      entryId: entryId,
      title: title,
      body: body,
    );
  }

  Future<void> deleteEntry(String entryId) {
    return _repository.deleteEntry(
      careGroupId: careGroupId,
      entryId: entryId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
