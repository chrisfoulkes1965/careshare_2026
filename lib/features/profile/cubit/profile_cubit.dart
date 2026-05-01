import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../care_group/models/care_group_option.dart";
import "../../invitations/repository/invitation_repository.dart";
import "../../user/models/home_sections_visibility.dart";
import "../../user/models/user_profile.dart";
import "../../user/repository/user_repository.dart";
import "../../../core/invite/pending_invitation_store.dart";
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

  /// Monotonic token so only the latest [_load] may emit — older in-flight loads
  /// (e.g. from sign-in) must not overwrite state after [completeInvitationProfile].
  int _profileLoadGeneration = 0;

  /// Non-null while [_load] is running for that uid — blocks duplicate [AuthBloc]
  /// `authenticated` emissions (token refresh) from starting a second hydrate.
  String? _profileHydrateInFlightUid;

  /// True during [completeInvitationProfile] until that flow finishes — including awaiting
  /// [InvitationRepository.redeemInvitationForSignedInUser] while state is already
  /// [ProfileLoading] but [_profileHydrateInFlightUid] has not yet been set. Blocks
  /// interleaved [_onAuthChanged] hydrates and pending-invite reads that would reopen
  /// [InviteProfileScreen] after redeem.
  bool _inviteRedeemWritesInProgress = false;

  /// Maps [AuthState.user] getters to [UserProfile] without importing Firebase in this cubit.
  UserProfile? _snapshotFromAuth(AuthState s) {
    final session = s.user;
    if (session == null) {
      return null;
    }
    final email = session.email ?? "";
    final dn = session.displayName?.trim();
    return UserProfile(
      uid: session.uid,
      email: email,
      displayName: (dn != null && dn.isNotEmpty) ? dn : _emailLocal(email),
      photoUrl: session.photoURL,
    );
  }

  /// Convenience: snapshot for the latest auth bloc state.
  UserProfile? _authSnapshotOrNull() => _snapshotFromAuth(_authBloc.state);

  Future<void> refresh() async {
    final snapshot = _authSnapshotOrNull();
    if (snapshot != null) {
      await _load(snapshot);
    }
  }

  /// Updates `careGroups/{careGroupId}.name` and reloads profile.
  Future<void> updateCareGroupName(String careGroupId, String name) async {
    final snapshot = _authSnapshotOrNull();
    if (snapshot == null) return;
    final previous = state;
    try {
      await _userRepository.updateCareGroupName(
        careGroupId: careGroupId,
        name: name,
      );
      await _load(snapshot);
    } catch (e) {
      if (previous is ProfileReady) {
        emit(previous);
      } else {
        emit(ProfileError(e.toString()));
      }
      rethrow;
    }
  }

  /// Writes `groupCalendar.{calendarId,icalUrl,timezone}` on `careGroups/{careGroupDocId}`.
  Future<void> mergeCareGroupCalendar({
    required String careGroupDocId,
    String? calendarId,
    String? icalUrl,
    String? timezone,
  }) async {
    final snapshot = _authSnapshotOrNull();
    if (snapshot == null) {
      return;
    }
    final previous = state;
    try {
      await _userRepository.mergeCareGroupCalendar(
        careGroupDocId: careGroupDocId,
        calendarId: calendarId,
        icalUrl: icalUrl,
        timezone: timezone,
      );
      await _load(snapshot);
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
    final snapshot = _authSnapshotOrNull();
    if (snapshot == null) return;
    final previous = state;
    try {
      await _userRepository.setCareGroupThemeColor(
        careGroupId: careGroupId,
        argb: argb,
      );
      await _load(snapshot);
    } catch (e) {
      if (previous is ProfileReady) {
        emit(previous);
      } else {
        emit(ProfileError(e.toString()));
      }
      rethrow;
    }
  }

  /// Persists which home landing sections to show (`users/{uid}.homeSections`).
  Future<void> setHomeSectionsVisibility(HomeSectionsVisibility visibility) async {
    final snapshot = _authSnapshotOrNull();
    if (snapshot == null) {
      return;
    }
    final previous = state;
    try {
      await _userRepository.setHomeSectionsVisibility(
        uid: snapshot.uid,
        visibility: visibility,
      );
      await _load(snapshot);
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
    final snapshot = _authSnapshotOrNull();
    if (snapshot == null) return;
    final previous = state;
    emit(const ProfileLoading());
    try {
      await _userRepository.setActiveCareGroup(
        uid: snapshot.uid,
        careGroupId: option.careGroupId,
      );
      await _load(snapshot);
    } catch (e) {
      if (previous is ProfileReady) {
        emit(previous);
      } else {
        emit(ProfileError(e.toString()));
      }
      rethrow;
    }
  }

  void _onAuthChanged(AuthState authState) {
    switch (authState.status) {
      case AuthStatus.unknown:
      case AuthStatus.unauthenticated:
        _profileLoadGeneration++;
        _profileHydrateInFlightUid = null;
        emit(const ProfileAnonymous());
      case AuthStatus.authenticated:
        final snapshot = _snapshotFromAuth(authState);
        if (snapshot == null) {
          break;
        }
        if (_inviteRedeemWritesInProgress) {
          break;
        }
        // Firebase `authStateChanges()` can re-emit `authenticated` (new [User] instance)
        // on token refresh. That must not queue another [_load] or we re-open the
        // invite gate while still on [#/loading] with `?invite=` in the document URL.
        final cur = state;
        if (cur is ProfileReady && cur.profile.uid == snapshot.uid) {
          return;
        }
        if (_profileHydrateInFlightUid == snapshot.uid) {
          return;
        }
        emit(const ProfileLoading());
        unawaited(_load(snapshot));
    }
  }

  Future<void> _load(
    UserProfile authIdentity, {
    bool ignorePendingInvitationStore = false,
  }) async {
    final gen = ++_profileLoadGeneration;
    _profileHydrateInFlightUid = authIdentity.uid;
    try {
      if (!_userRepository.isAvailable) {
        if (gen != _profileLoadGeneration) {
          return;
        }
        emit(
          ProfileReady(
            UserProfile(
              uid: authIdentity.uid,
              email: authIdentity.email,
              displayName: authIdentity.displayName.isNotEmpty
                  ? authIdentity.displayName
                  : _emailLocal(authIdentity.email),
              photoUrl: authIdentity.photoUrl,
              wizardCompleted: true,
              wizardSkipped: true,
            ),
          ),
        );
        return;
      }

      try {
        await _userRepository
          .ensureUserDocument(authIdentity)
          .timeout(const Duration(seconds: 12));
      if (gen != _profileLoadGeneration) {
        return;
      }
      var profile = await _userRepository
          .fetchProfile(authIdentity.uid)
          .timeout(const Duration(seconds: 12));
      if (gen != _profileLoadGeneration) {
        return;
      }
      profile ??= UserProfile(
        uid: authIdentity.uid,
        email: authIdentity.email,
        displayName: authIdentity.displayName.isNotEmpty
            ? authIdentity.displayName
            : _emailLocal(authIdentity.email),
        photoUrl: authIdentity.photoUrl,
      );
      var trimmedDefer = "";
      if (!ignorePendingInvitationStore && !_inviteRedeemWritesInProgress) {
        trimmedDefer = (await PendingInvitationStore.read())?.trim() ?? "";
        if (trimmedDefer.isNotEmpty && _invitationRepository.isAvailable) {
          try {
            final stillPending = await _invitationRepository
                .invitationIsAwaitingAcceptance(trimmedDefer);
            if (!stillPending) {
              await PendingInvitationStore.clear();
              trimmedDefer = "";
            }
          } catch (_) {
            // Offline or rules: keep invite flow so we do not wipe a valid id.
          }
        }
        if (gen != _profileLoadGeneration) {
          return;
        }
        // Another flow may clear [PendingInvitationStore] while we await Firestore.
        trimmedDefer = (await PendingInvitationStore.read())?.trim() ?? "";
        if (trimmedDefer.isNotEmpty &&
            await PendingInvitationStore.isRecordedAsRedeemed(trimmedDefer)) {
          await PendingInvitationStore.clear();
          trimmedDefer = "";
        }
      }
      if (gen != _profileLoadGeneration) {
        return;
      }
      final hasPendingInvite =
          !ignorePendingInvitationStore &&
              !_inviteRedeemWritesInProgress &&
              _invitationRepository.isAvailable &&
              trimmedDefer.isNotEmpty;

      // Redemption runs only from [completeInvitationProfile], not here — so invitees
      // always confirm name/avatar on InviteProfileScreen after following a link.
      await _emitWithCareGroupOptions(
        authIdentity,
        profile,
        loadGeneration: gen,
        deferredInvitationId: hasPendingInvite ? trimmedDefer : null,
      );
    } on TimeoutException {
      if (gen != _profileLoadGeneration) {
        return;
      }
      emit(const ProfileError("Profile load timed out. Please retry."));
    } catch (e) {
      if (gen != _profileLoadGeneration) {
        return;
      }
      emit(ProfileError(e.toString()));
    }
    } finally {
      if (_profileHydrateInFlightUid == authIdentity.uid) {
        _profileHydrateInFlightUid = null;
      }
    }
  }

  Future<void> _emitWithCareGroupOptions(
    UserProfile authIdentity,
    UserProfile profile, {
    required int loadGeneration,
    String? deferredInvitationId,
  }) async {
    var p = profile;
    List<CareGroupOption> options = const [];
    try {
      options = await _userRepository
          .listCareGroupsForUser(authIdentity.uid)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      options = const [];
    } catch (_) {
      options = const [];
    }
    if (loadGeneration != _profileLoadGeneration) {
      return;
    }

    // The collection-group "members" query can return [] until indexes deploy, or if it
    // errors — but [UserProfile] may already have [activeCareGroupId] from the wizard.
    if (p.activeCareGroupId != null && p.activeCareGroupId!.isNotEmpty) {
      final hasTeam = options.any((o) => o.careGroupId == p.activeCareGroupId);
      if (!hasTeam) {
        try {
          final repair = await _userRepository
              .fetchCareGroupOptionForActiveProfile(
                uid: authIdentity.uid,
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
    if (loadGeneration != _profileLoadGeneration) {
      return;
    }

    // If the user belongs to exactly one team and has no active group chosen, attach them.
    // Do NOT force-set [only] when [activeCareGroupId] is already nonempty but differs —
    // that happens briefly after redeeming an invite (new membership appears in profile before
    // the collection-group "members" query lists the invited group).
    if (options.length == 1) {
      final only = options.first;
      final activeTrim = (p.activeCareGroupId ?? "").trim();
      if (activeTrim.isEmpty) {
        await _userRepository.setActiveCareGroup(
          uid: authIdentity.uid,
          careGroupId: only.careGroupId,
        );
        if (loadGeneration != _profileLoadGeneration) {
          return;
        }
        final again = await _userRepository.fetchProfile(authIdentity.uid);
        if (again != null) {
          p = again;
        }
      }
    }
    if (loadGeneration != _profileLoadGeneration) {
      return;
    }

    final pendingId = deferredInvitationId?.trim();
    final hasPending = pendingId != null && pendingId.isNotEmpty;

    if (hasPending && _invitationRepository.isAvailable) {
      unawaited(_invitationRepository.recordInviteeOnboardingMilestonesIfUnset(
        pendingId,
      ));

      // Auto-redeem: no separate "welcome" screen. Use the user's existing
      // displayName / avatar (from registration or profile), default to email
      // local-part for the name. Leave [avatarIndex] null so the avatar widget
      // renders the user's initials until they pick one in Settings.
      final dn = p.displayName.trim().isNotEmpty
          ? p.displayName.trim()
          : _emailLocal(p.email);
      final int? ai =
          (p.avatarIndex != null && p.avatarIndex! >= 1) ? p.avatarIndex : null;

      try {
        _inviteRedeemWritesInProgress = true;
        final cgId =
            await _invitationRepository.redeemInvitationForSignedInUser(
          invitationId: pendingId,
          displayName: dn,
          avatarIndex: ai,
        );
        if (loadGeneration != _profileLoadGeneration) {
          return;
        }
        if (cgId != null && cgId.isNotEmpty) {
          // Also write displayName/avatar/wizardSkipped on /users/{uid} so
          // home / settings render consistently.
          try {
            await _userRepository.updateProfileFields(authIdentity.uid, {
              "displayName": dn,
              "wizardSkipped": true,
            });
          } catch (_) {
            // tolerate; profile already loaded with fallback values
          }
          if (ai != null &&
              ai >= 1 &&
              (p.avatarIndex == null || p.avatarIndex! < 1)) {
            try {
              await _userRepository.setAvatarPreset(authIdentity.uid, ai);
            } catch (_) {
              // ignore — avatar is cosmetic, do not block joining the team
            }
          }
          await PendingInvitationStore.clearAfterInvitationRedeem(pendingId);

          try {
            await _userRepository.setActiveCareGroup(
              uid: authIdentity.uid,
              careGroupId: cgId,
            );
          } catch (_) {
            // tolerate; selection screen will appear if needed
          }

          // Refresh local profile snapshot for the post-redeem emit.
          try {
            final again = await _userRepository.fetchProfile(authIdentity.uid);
            if (again != null) {
              p = again;
            }
          } catch (_) {/* keep p */}

          // Refresh care group options now that membership exists.
          try {
            final freshOptions = await _userRepository
                .listCareGroupsForUser(authIdentity.uid)
                .timeout(const Duration(seconds: 12));
            options = freshOptions;
          } catch (_) {/* keep options */}

          // The collection-group `members` query can lag on the very first read
          // after a transactional create — fall back to a direct
          // `careGroups/{cgId}` + `members/{uid}` get so the home header has
          // the team name immediately instead of "New Caregroup".
          if (!options.any((o) => o.careGroupId == cgId)) {
            try {
              final repaired = await _userRepository
                  .fetchCareGroupOptionForActiveProfile(
                    uid: authIdentity.uid,
                    careGroupId: cgId,
                  )
                  .timeout(const Duration(seconds: 12));
              if (repaired != null) {
                options = [...options, repaired]..sort(
                    (a, b) => a.displayName
                        .toLowerCase()
                        .compareTo(b.displayName.toLowerCase()),
                  );
              }
            } catch (_) {/* keep options */}
          }

          _justAcceptedCareGroupId = cgId;
        }
      } catch (e, st) {
        // Redeem failed (rules / network) — land the user on home anyway so
        // they're not stuck on a "welcome" loop. The pending id stays in
        // PendingInvitationStore so a manual retry from settings can re-run it.
        _justFailedInviteRedeemError = e.toString();
        // Keep stack trace surface for devtools console.
        // ignore: avoid_print
        print("ProfileCubit: invite auto-redeem failed: $e\n$st");
      } finally {
        _inviteRedeemWritesInProgress = false;
      }

      // Even if redeem failed, mark wizard as skipped so the invitee isn't
      // dropped into "Who is being cared for" (the new-care-group wizard).
      // They can retry the invite from Settings or be re-invited.
      if (!p.wizardSkipped && !p.wizardCompleted) {
        try {
          await _userRepository.updateProfileFields(authIdentity.uid, {
            "wizardSkipped": true,
          });
          final again = await _userRepository.fetchProfile(authIdentity.uid);
          if (again != null) {
            p = again;
          }
        } catch (_) {/* tolerate */}
      }
    }

    final active = p.activeCareGroupId;
    final requiresAfter = options.length > 1 &&
        (active == null ||
            active.isEmpty ||
            !options.any((o) => o.careGroupId == active));

    emit(
      ProfileReady(
        p,
        careGroupOptions: options,
        requiresCareGroupSelection: requiresAfter,
      ),
    );

    // Mirror profile photo / preset avatar into each `members/{uid}` doc (readable by the group).
    unawaited(
      _userRepository
          .syncMemberRosterFromProfile(uid: authIdentity.uid, profile: p)
          .catchError((_) {}),
    );
  }

  /// Care group id the user just joined via auto-redeem (consumed by
  /// [HomeLandingView] for a one-time welcome snackbar).
  String? _justAcceptedCareGroupId;
  String? consumeJustAcceptedCareGroupId() {
    final v = _justAcceptedCareGroupId;
    _justAcceptedCareGroupId = null;
    return v;
  }

  /// Error message from the most recent failed auto-redeem attempt.
  String? _justFailedInviteRedeemError;
  String? consumeJustFailedInviteRedeemError() {
    final v = _justFailedInviteRedeemError;
    _justFailedInviteRedeemError = null;
    return v;
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
