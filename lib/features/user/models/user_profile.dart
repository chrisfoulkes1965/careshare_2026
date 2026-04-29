import "package:equatable/equatable.dart";

import "home_sections_visibility.dart";

final class UserProfile extends Equatable {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.avatarIndex,
    this.simpleMode = false,
    this.wizardCompleted = false,
    this.wizardSkipped = false,
    this.activeCareGroupId,
    this.wizardDraft,
    this.homeSections,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int? avatarIndex;
  final bool simpleMode;
  final bool wizardCompleted;
  final bool wizardSkipped;
  final String? activeCareGroupId;
  final Map<String, dynamic>? wizardDraft;

  /// When absent, treat as “show all” sections on the home landing page.
  final HomeSectionsVisibility? homeSections;

  bool get needsWizard => !wizardCompleted && !wizardSkipped;

  HomeSectionsVisibility get resolvedHomeSections =>
      homeSections ?? const HomeSectionsVisibility();

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    int? avatarIndex,
    bool? simpleMode,
    bool? wizardCompleted,
    bool? wizardSkipped,
    String? activeCareGroupId,
    Map<String, dynamic>? wizardDraft,
    HomeSectionsVisibility? homeSections,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      simpleMode: simpleMode ?? this.simpleMode,
      wizardCompleted: wizardCompleted ?? this.wizardCompleted,
      wizardSkipped: wizardSkipped ?? this.wizardSkipped,
      activeCareGroupId: activeCareGroupId ?? this.activeCareGroupId,
      wizardDraft: wizardDraft ?? this.wizardDraft,
      homeSections: homeSections ?? this.homeSections,
    );
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        displayName,
        photoUrl,
        avatarIndex,
        simpleMode,
        wizardCompleted,
        wizardSkipped,
        activeCareGroupId,
        wizardDraft,
        homeSections,
      ];
}
