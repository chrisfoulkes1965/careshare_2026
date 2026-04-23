import "package:equatable/equatable.dart";

import "../models/household_task.dart";

sealed class TasksState extends Equatable {
  const TasksState();

  @override
  List<Object?> get props => [];
}

final class TasksInitial extends TasksState {
  const TasksInitial();
}

final class TasksLoading extends TasksState {
  const TasksLoading();
}

final class TasksEmpty extends TasksState {
  const TasksEmpty();
}

final class TasksDisplay extends TasksState {
  const TasksDisplay({required this.list});

  final List<HouseholdTask> list;

  @override
  List<Object?> get props => [list];
}

final class TasksFailure extends TasksState {
  const TasksFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
