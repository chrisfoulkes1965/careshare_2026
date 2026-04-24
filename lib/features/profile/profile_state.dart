import "package:equatable/equatable.dart";

import "../care_group/models/care_group_option.dart";
import "../user/models/user_profile.dart";

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
  /// valid [UserProfile.activeCareGroupId] / [UserProfile.activeHouseholdId] (or [selectActiveCareGroup] has not been called yet).
  final bool requiresCareGroupSelection;

  @override
  List<Object?> get props => [profile, careGroupOptions, requiresCareGroupSelection];
}

final class ProfileError extends ProfileState {
  const ProfileError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
