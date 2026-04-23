import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../models/household_contact.dart";
import "../repository/contacts_repository.dart";
import "contacts_state.dart";

final class ContactsCubit extends Cubit<ContactsState> {
  ContactsCubit({
    required ContactsRepository repository,
    required this.householdId,
  })  : _repository = repository,
        super(const ContactsInitial());

  final ContactsRepository _repository;
  final String householdId;

  StreamSubscription<List<HouseholdContact>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const ContactsFailure("Firebase is not available."));
      return;
    }
    emit(const ContactsLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchContacts(householdId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const ContactsEmpty());
        } else {
          emit(ContactsDisplay(list: list));
        }
      },
      onError: (Object e) => emit(ContactsFailure(e.toString())),
    );
  }

  Future<void> addContact({
    required String name,
    String phone = "",
    String email = "",
    String notes = "",
  }) {
    return _repository.addContact(
      householdId: householdId,
      name: name,
      phone: phone,
      email: email,
      notes: notes,
    );
  }

  Future<void> updateContact({
    required String contactId,
    required String name,
    String phone = "",
    String email = "",
    String notes = "",
  }) {
    return _repository.updateContact(
      householdId: householdId,
      contactId: contactId,
      name: name,
      phone: phone,
      email: email,
      notes: notes,
    );
  }

  Future<void> deleteContact(String contactId) {
    return _repository.deleteContact(
      householdId: householdId,
      contactId: contactId,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
