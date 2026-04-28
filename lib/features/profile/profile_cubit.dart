import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../auth/bloc/auth_bloc.dart";
import "../auth/bloc/auth_state.dart";
import "../care_group/models/care_group_option.dart";
import "../invitations/repository/invitation_repository.dart";
import "../user/models/user_profile.dart";
import "../user/repository/user_repository.dart";
import "../../core/invite/pending_invitation_store.dart";
import "profile_state.dart";

final class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required AuthBloc authBloc,
    required UserRepository userRepository,
    required InvitationRepository invitationRepository,
  })  : _authBloc = authBloc,
        _userRepository = userRepository,
        _invitationRepository = invitationRepository,
        super(const ProfileAnonymous()) {
    _authSub = _authBloc.stream.listen(_onAuthChanged);
    _onAuthChanged(_authBloc.state);
  }

  final AuthBloc _authBloc;
  final UserRepository _userRepository;
  final InvitationRepository _invitationRepository;
  late final StreamSubscription<AuthState> _authSub;

  Future<void> refresh() async {
    final user = _authBloc.state.user;
    if (user != null) {
      await _load(user);
    }
  }

  /// Updates `careGroups/{careGroupId}.name` and reloads profile.
  Future<void> updateCareGroupName(String careGroupId, String name) async {
    final user = _authBloc.state.user;
    if (user == null) return;
    final previous = state;
    try {
      await _userRepository.updateCareGroupName(
        careGroupId: careGroupId,
        name: name,
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

  /// Updates `careGroups/{careGroupId}.themeColor` (or clears it) and reloads profile.
  Future<void> setCareGroupThemeColor(String careGroupId, int? argb) async {
    final user = _authBloc.state.user;
    if (user == null) return;
    final previous = state;
    try {
      await _userRepository.setCareGroupThemeColor(
        careGroupId: careGroupId,
        argb: argb,
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

  /// Picks a care group after login or from settings; updates Firestore and reloads profile.
  Future<void> selectActiveCareGroup(CareGroupOption option) async {
    final user = _authBloc.state.user;
    if (user == null) return;
    final previous = state;
    emit(const ProfileLoading());
    try {
      await _userRepository.setActiveCareGroup(
        uid: user.uid,
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
      var profile = await _userRepository
          .fetchProfile(user.uid)
          .timeout(const Duration(seconds: 12));
      profile ??= UserProfile(
        uid: user.uid,
        email: user.email ?? "",
        displayName: user.displayName ?? _emailLocal(user.email),
        photoUrl: user.photoURL,
      );
      profile = await _maybeRedeemInvitationFromEmailLink(user, profile);
      await _emitWithCareGroupOptions(user, profile);
    } on TimeoutException {
      emit(const ProfileError("Profile load timed out. Please retry."));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<UserProfile> _maybeRedeemInvitationFromEmailLink(
    User user,
    UserProfile profile,
  ) async {
    if (!_invitationRepository.isAvailable) {
      return profile;
    }
    final id = await PendingInvitationStore.read();
    if (id == null) {
      return profile;
    }
    try {
      final careGroupId =
          await _invitationRepository.redeemInvitationForSignedInUser(
        invitationId: id,
        displayName: profile.displayName,
      );
      await PendingInvitationStore.clear();
      if (careGroupId != null && careGroupId.isNotEmpty) {
        await _userRepository.setActiveCareGroup(
          uid: user.uid,
          careGroupId: careGroupId,
        );
        final updated = await _userRepository.fetchProfile(user.uid);
        return updated ?? profile.copyWith(activeCareGroupId: careGroupId);
      }
    } catch (_) {
      await PendingInvitationStore.clear();
    }
    return profile;
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

    // The collection-group "members" query can return [] until indexes deploy, or if it
    // errors — but [UserProfile] may already have [activeCareGroupId] from the wizard.
    if (p.activeCareGroupId != null && p.activeCareGroupId!.isNotEmpty) {
      final hasTeam = options.any((o) => o.careGroupId == p.activeCareGroupId);
      if (!hasTeam) {
        try {
          final repair = await _userRepository
              .fetchCareGroupOptionForActiveProfile(
            uid: user.uid,
            careGroupId: p.activeCareGroupId!,
          )
              .timeout(const Duration(seconds: 12));
          if (repair != null) {
            options = [...options, repair]..sort(
                (a, b) => a.displayName
                    .toLowerCase()
                    .compareTo(b.displayName.toLowerCase()),
              );
          }
        } on TimeoutException {
          // keep options as-is
        } catch (_) {
          // keep options as-is
        }
      }
    }

    if (options.length == 1) {
      final only = options.first;
      if (p.activeCareGroupId != only.careGroupId) {
        await _userRepository.setActiveCareGroup(
          uid: user.uid,
          careGroupId: only.careGroupId,
        );
        final again = await _userRepository.fetchProfile(user.uid);
        if (again != null) {
          p = again;
        }
      }
    }

    final active = p.activeCareGroupId;
    final requires = options.length > 1 &&
        (active == null ||
            active.isEmpty ||
            !options.any((o) => o.careGroupId == active));

    emit(
      ProfileReady(
        p,
        careGroupOptions: options,
        requiresCareGroupSelection: requires,
      ),
    );

    // Mirror profile photo / preset avatar into each `members/{uid}` doc (readable by the group).
    unawaited(
      _userRepository
          .syncMemberRosterFromProfile(uid: user.uid, profile: p)
          .catchError((_) {}),
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
