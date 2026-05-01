import "package:equatable/equatable.dart";

import "../../care_group/models/care_group_option.dart";
import "../../user/models/user_profile.dart";

sealed class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object?> get props => [];
}

final class ProfileAnonymous extends ProfileState {
  const ProfileAnonymous();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileReady extends ProfileState {
  const ProfileReady(
    this.profile, {
    this.careGroupOptions = const [],
    this.requiresCareGroupSelection = false,
  });

  final UserProfile profile;
  final List<CareGroupOption> careGroupOptions;

  /// When true, the user has more than one care group to choose from and must pick
  /// valid [UserProfile.activeCareGroupId] (or [selectActiveCareGroup] has not been called yet).
  final bool requiresCareGroupSelection;

  @override
  List<Object?> get props => [
        profile,
        careGroupOptions,
        requiresCareGroupSelection,
      ];
}

/// Display name of the [UserProfile.activeCareGroupId] within [ProfileReady.careGroupOptions].
extension ProfileReadyActiveCareGroup on ProfileReady {
  String? get activeCareGroupDisplayName {
    final id = profile.activeCareGroupId;
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final o in careGroupOptions) {
      if (o.careGroupId == id) {
        return o.displayName;
      }
    }
    return null;
  }

  /// `careGroups` document `themeColor` (ARGB) for the active home, or null to use the default.
  int? get activeCareGroupThemeArgb {
    final id = profile.activeCareGroupId;
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final o in careGroupOptions) {
      if (o.careGroupId == id) {
        return o.themeColor;
      }
    }
    return null;
  }

  /// The active [CareGroupOption], if it appears in [careGroupOptions].
  CareGroupOption? get activeCareGroupOption {
    final id = profile.activeCareGroupId;
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final o in careGroupOptions) {
      if (o.careGroupId == id) {
        return o;
      }
    }
    return null;
  }

  /// `careGroups/{id}/members` — document id for the member list (and roles). Matches
  /// [UserProfile.activeCareGroupId] / [CareGroupOption.careGroupId] (the document that
  /// holds the user's [members] row), not the linked [CareGroupOption.dataCareGroupId].
  String? get activeCareGroupMemberDocId {
    final opt = activeCareGroupOption;
    if (opt != null) {
      return opt.careGroupId;
    }
    final id = profile.activeCareGroupId;
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }

  /// `careGroups/{id}` for **data** subcollections: tasks, notes, journal, chat, expenses, etc.
  ///
  /// When two [careGroups] documents are cross-linked, the profile id is the [members/]
  /// document, but shared data can live on the linked document ([CareGroupOption.dataCareGroupId]).
  /// Then this returns [CareGroupOption.dataCareGroupId]; for a single merged doc, it matches
  /// [activeCareGroupMemberDocId]. Use [activeCareGroupMemberDocId] for [members/] only.
  String? get activeCareGroupDataId {
    final opt = activeCareGroupOption;
    if (opt != null) {
      final d = opt.dataCareGroupId.trim();
      if (d.isNotEmpty) {
        return d;
      }
      return opt.careGroupId;
    }
    final id = profile.activeCareGroupId;
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }
}

final class ProfileError extends ProfileState {
  const ProfileError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
