import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../models/care_group_member.dart";
import "../repository/members_repository.dart";
import "members_state.dart";

final class MembersCubit extends Cubit<MembersState> {
  MembersCubit({
    required MembersRepository repository,
    required this.careGroupId,
  })  : _repository = repository,
        super(const MembersInitial());

  final MembersRepository _repository;
  final String careGroupId;

  StreamSubscription<List<CareGroupMember>>? _sub;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const MembersFailure("Firebase is not available."));
      return;
    }
    emit(const MembersLoading());
    unawaited(_sub?.cancel());
    _sub = _repository.watchMembers(careGroupId).listen(
      (list) {
        if (list.isEmpty) {
          emit(const MembersEmpty());
        } else {
          emit(MembersDisplay(list: list));
        }
      },
      onError: (Object e) => emit(MembersFailure(e.toString())),
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
