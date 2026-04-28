import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../models/care_group_expense.dart";
import "../repository/expenses_repository.dart";
import "expenses_state.dart";

final class ExpensesCubit extends Cubit<ExpensesState> {
  ExpensesCubit({
    required ExpensesRepository repository,
    required this.careGroupId,
  })  : _repository = repository,
        super(const ExpensesInitial());

  final ExpensesRepository _repository;
  final String careGroupId;

  StreamSubscription<List<CareGroupExpense>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const ExpensesFailure("Firebase is not available."));
      return;
    }
    emit(const ExpensesLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchExpenses(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const ExpensesEmpty());
        } else {
          emit(ExpensesDisplay(list: list));
        }
      },
      onError: (Object e) => emit(ExpensesFailure(e.toString())),
    );
  }

  Future<void> refresh() async {
    subscribe();
  }

  Future<void> addExpense({
    required String title,
    required double amount,
    required String currency,
    required DateTime spentAt,
    String? category,
    String? payee,
    String? notes,
    PlatformFile? receipt,
  }) async {
    final id = await _repository.addExpense(
      careGroupId: careGroupId,
      title: title,
      amount: amount,
      currency: currency,
      spentAt: spentAt,
      category: category,
      payee: payee,
      notes: notes,
    );
    if (receipt != null && id.isNotEmpty) {
      await _repository.uploadAndSetReceipt(
        careGroupId: careGroupId,
        expenseId: id,
        file: receipt,
      );
    }
  }

  Future<void> updateExpense({
    required String expenseId,
    required String title,
    required double amount,
    required String currency,
    required DateTime spentAt,
    String? category,
    String? payee,
    String? notes,
    PlatformFile? receipt,
    bool removeReceipt = false,
    String? previousReceiptUrl,
  }) async {
    await _repository.updateExpense(
      careGroupId: careGroupId,
      expenseId: expenseId,
      title: title,
      amount: amount,
      currency: currency,
      spentAt: spentAt,
      category: category,
      payee: payee,
      notes: notes,
    );
    if (removeReceipt) {
      await _repository.clearReceiptUrl(
        careGroupId: careGroupId,
        expenseId: expenseId,
        previousDownloadUrl: previousReceiptUrl,
      );
    } else if (receipt != null) {
      await _repository.uploadAndSetReceipt(
        careGroupId: careGroupId,
        expenseId: expenseId,
        file: receipt,
      );
    }
  }

  Future<void> deleteExpense(String expenseId) {
    return _repository.deleteExpense(
      careGroupId: careGroupId,
      expenseId: expenseId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
