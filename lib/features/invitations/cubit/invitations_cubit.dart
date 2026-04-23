import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../models/care_invitation.dart";
import "../repository/invitation_repository.dart";
import "invitations_state.dart";

final class InvitationsCubit extends Cubit<InvitationsState> {
  InvitationsCubit({
    required InvitationRepository repository,
    required this.careGroupId,
    required this.householdId,
  })  : _repository = repository,
        super(const InvitationsInitial());

  final InvitationRepository _repository;
  final String careGroupId;
  final String householdId;

  StreamSubscription<List<CareInvitation>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const InvitationsFailure("Firebase is not available."));
      return;
    }
    emit(const InvitationsLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchByCareGroup(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const InvitationsEmpty());
        } else {
          emit(InvitationsDisplay(list: list));
        }
      },
      onError: (Object e) => emit(InvitationsFailure(e.toString())),
    );
  }

  Future<void> invite(String email) {
    return _repository.createInvitation(
      careGroupId: careGroupId,
      householdId: householdId,
      email: email,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
