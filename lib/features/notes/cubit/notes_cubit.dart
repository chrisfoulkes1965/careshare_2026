import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../models/household_note.dart";
import "../repository/notes_repository.dart";
import "notes_state.dart";

final class NotesCubit extends Cubit<NotesState> {
  NotesCubit({
    required NotesRepository repository,
    required this.careGroupId,
  })  : _repository = repository,
        super(const NotesInitial());

  final NotesRepository _repository;
  final String careGroupId;

  StreamSubscription<List<CareGroupNote>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const NotesFailure("Firebase is not available."));
      return;
    }
    emit(const NotesLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchNotes(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const NotesEmpty());
        } else {
          emit(NotesDisplay(list: list));
        }
      },
      onError: (Object e) => emit(NotesFailure(e.toString())),
    );
  }

  Future<void> addNote({
    required String title,
    required String type,
    String body = "",
    String? legalCategory,
  }) {
    return _repository.addNote(
      careGroupId: careGroupId,
      title: title,
      type: type,
      body: body,
      legalCategory: legalCategory,
    );
  }

  Future<void> updateNote({
    required String noteId,
    required String title,
    required String type,
    required String body,
    String? legalCategory,
  }) {
    return _repository.updateNote(
      careGroupId: careGroupId,
      noteId: noteId,
      title: title,
      type: type,
      body: body,
      legalCategory: legalCategory,
    );
  }

  Future<void> deleteNote(String noteId) {
    return _repository.deleteNote(
      careGroupId: careGroupId,
      noteId: noteId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
