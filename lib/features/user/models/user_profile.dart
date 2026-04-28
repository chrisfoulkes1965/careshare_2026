import "package:equatable/equatable.dart";

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

  bool get needsWizard => !wizardCompleted && !wizardSkipped;

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    int? avatarIndex,
    bool? simpleMode,
    bool? wizardCompleted,
    bool? wizardSkipped,
    String? activeCareGroupId,
    Map<String, dynamic>? wizardDraft,
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
      ];
}
