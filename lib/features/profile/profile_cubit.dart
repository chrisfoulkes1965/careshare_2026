import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../auth/bloc/auth_bloc.dart";
import "../auth/bloc/auth_state.dart";
import "../care_group/models/care_group_option.dart";
import "../user/models/user_profile.dart";
import "../user/repository/user_repository.dart";
import "profile_state.dart";

final class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required AuthBloc authBloc,
    required UserRepository userRepository,
  })  : _authBloc = authBloc,
        _userRepository = userRepository,
        super(const ProfileAnonymous()) {
    _authSub = _authBloc.stream.listen(_onAuthChanged);
    _onAuthChanged(_authBloc.state);
  }

  final AuthBloc _authBloc;
  final UserRepository _userRepository;
  late final StreamSubscription<AuthState> _authSub;

  Future<void> refresh() async {
    final user = _authBloc.state.user;
    if (user != null) {
      await _load(user);
    }
  }

  /// Picks a care group after login or from settings; updates Firestore and reloads profile.
  Future<void> selectActiveCareGroup(CareGroupOption option) async {
    final user = _authBloc.state.user;
    if (user == null) return;
    final previous = state;
    emit(const ProfileLoading());
    try {
      await _userRepository.setActiveCareGroup(
        uid: user.uid,
        householdId: option.householdId,
        careGroupId: option.careGroupId,
      );
      await _load(user);
    } catch (e) {
      if (previous is ProfileReady) {
        emit(previous);
      } else {
        emit(ProfileError(e.toString()));
      }
      rethrow;
    }
  }

  void _onAuthChanged(AuthState state) {
    switch (state.status) {
      case AuthStatus.unknown:
        emit(const ProfileAnonymous());
      case AuthStatus.unauthenticated:
        emit(const ProfileAnonymous());
      case AuthStatus.authenticated:
        final user = state.user;
        if (user != null) {
          emit(const ProfileLoading());
          unawaited(_load(user));
        }
    }
  }

  Future<void> _load(User user) async {
    if (!_userRepository.isAvailable) {
      emit(
        ProfileReady(
          UserProfile(
            uid: user.uid,
            email: user.email ?? "",
            displayName: user.displayName ?? _emailLocal(user.email),
            photoUrl: user.photoURL,
            wizardCompleted: true,
            wizardSkipped: true,
          ),
        ),
      );
      return;
    }

    try {
      await _userRepository
          .ensureUserDocument(user)
          .timeout(const Duration(seconds: 12));
      final fetched = await _userRepository
          .fetchProfile(user.uid)
          .timeout(const Duration(seconds: 12));
      if (fetched != null) {
        await _emitWithCareGroupOptions(user, fetched);
        return;
      }

      final fallback = UserProfile(
        uid: user.uid,
        email: user.email ?? "",
        displayName: user.displayName ?? _emailLocal(user.email),
        photoUrl: user.photoURL,
      );
      await _emitWithCareGroupOptions(user, fallback);
    } on TimeoutException {
      emit(const ProfileError("Profile load timed out. Please retry."));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _emitWithCareGroupOptions(User user, UserProfile profile) async {
    var p = profile;
    List<CareGroupOption> options = const [];
    try {
      options = await _userRepository
          .listCareGroupsForUser(user.uid)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      options = const [];
    } catch (_) {
      options = const [];
    }

    if (options.length == 1) {
      final only = options.first;
      if (p.activeHouseholdId != only.householdId || p.activeCareGroupId != only.careGroupId) {
        await _userRepository.setActiveCareGroup(
          uid: user.uid,
          householdId: only.householdId,
          careGroupId: only.careGroupId,
        );
        final again = await _userRepository.fetchProfile(user.uid);
        if (again != null) {
          p = again;
        }
      }
    }

    final active = p.activeHouseholdId;
    final requires = options.length > 1 &&
        (active == null ||
            active.isEmpty ||
            !options.any((o) => o.householdId == active));

    emit(
      ProfileReady(
        p,
        careGroupOptions: options,
        requiresCareGroupSelection: requires,
      ),
    );
  }

  String _emailLocal(String? email) {
    if (email == null || email.isEmpty) return "Carer";
    final at = email.indexOf("@");
    if (at <= 0) return "Carer";
    return email.substring(0, at);
  }

  @override
  Future<void> close() async {
    await _authSub.cancel();
    return super.close();
  }
}
