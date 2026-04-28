import "package:equatable/equatable.dart";

import "../models/care_group_expense.dart";

sealed class ExpensesState extends Equatable {
  const ExpensesState();

  @override
  List<Object?> get props => [];
}

final class ExpensesInitial extends ExpensesState {
  const ExpensesInitial();
}

final class ExpensesLoading extends ExpensesState {
  const ExpensesLoading();
}

final class ExpensesEmpty extends ExpensesState {
  const ExpensesEmpty();
}

final class ExpensesDisplay extends ExpensesState {
  const ExpensesDisplay({required this.list});

  final List<CareGroupExpense> list;

  @override
  List<Object?> get props => [list];
}

final class ExpensesFailure extends ExpensesState {
  const ExpensesFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
