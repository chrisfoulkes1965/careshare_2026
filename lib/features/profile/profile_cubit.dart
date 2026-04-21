import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../auth/bloc/auth_bloc.dart";
import "../auth/bloc/auth_state.dart";
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
      await _userRepository.ensureUserDocument(user);
      final fetched = await _userRepository.fetchProfile(user.uid);
      if (fetched != null) {
        emit(ProfileReady(fetched));
        return;
      }

      emit(
        ProfileReady(
          UserProfile(
            uid: user.uid,
            email: user.email ?? "",
            displayName: user.displayName ?? _emailLocal(user.email),
            photoUrl: user.photoURL,
          ),
        ),
      );
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
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
