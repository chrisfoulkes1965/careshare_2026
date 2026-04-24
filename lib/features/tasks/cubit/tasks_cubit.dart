import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../models/household_task.dart";
import "../repository/task_repository.dart";
import "tasks_state.dart";

final class TasksCubit extends Cubit<TasksState> {
  TasksCubit({
    required TaskRepository repository,
    required this.careGroupId,
  })  : _repository = repository,
        super(const TasksInitial());

  final TaskRepository _repository;
  final String careGroupId;

  StreamSubscription<List<CareGroupTask>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const TasksFailure("Firebase is not available."));
      return;
    }
    emit(const TasksLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchTasks(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const TasksEmpty());
        } else {
          emit(TasksDisplay(list: list));
        }
      },
      onError: (Object e) => emit(TasksFailure(e.toString())),
    );
  }

  Future<String> addTask({
    required String title,
    String? assignedTo,
    String notes = '',
    DateTime? dueAt,
    List<PlatformFile> attachments = const [],
  }) {
    return _repository.addTask(
      careGroupId: careGroupId,
      title: title,
      assignedTo: assignedTo,
      notes: notes,
      dueAt: dueAt,
      attachments: attachments,
    );
  }

  Future<void> updateTask({
    required String taskId,
    required String title,
    String notes = '',
    DateTime? dueAt,
    String? assignedTo,
    List<PlatformFile> newAttachments = const [],
  }) {
    return _repository.updateTask(
      careGroupId: careGroupId,
      taskId: taskId,
      title: title,
      notes: notes,
      dueAt: dueAt,
      assignedTo: assignedTo,
      newAttachments: newAttachments,
    );
  }

  Future<void> setDone(String taskId, bool done) {
    return _repository.setTaskDone(
      careGroupId: careGroupId,
      taskId: taskId,
      done: done,
    );
  }

  Future<void> deleteTask(String taskId) {
    return _repository.deleteTask(
      careGroupId: careGroupId,
      taskId: taskId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
