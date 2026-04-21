import "package:equatable/equatable.dart";

import "../../user/models/user_profile.dart";
import "../models/setup_models.dart";

enum SetupWizardStep {
  welcome,
  pathways,
  household,
  invites,
  avatar,
  summary,
}

final class SetupWizardState extends Equatable {
  const SetupWizardState({
    required this.step,
    required this.selectedPathwayIds,
    required this.householdName,
    required this.householdDescription,
    required this.recipients,
    required this.inviteEmails,
    required this.inviteEmailInput,
    this.avatarIndex = 1,
    this.isSubmitting = false,
    this.errorMessage,
  });

  factory SetupWizardState.initial() {
    return SetupWizardState(
      step: SetupWizardStep.welcome,
      selectedPathwayIds: const {},
      householdName: "",
      householdDescription: "",
      recipients: [
        RecipientDraft(
          id: newRecipientId(),
          displayName: "",
          accessMode: RecipientAccessMode.managed,
        ),
      ],
      inviteEmails: const [],
      inviteEmailInput: "",
      avatarIndex: 1,
    );
  }

  factory SetupWizardState.fromProfile(UserProfile profile) {
    final draft = profile.wizardDraft;
    if (draft == null) {
      return SetupWizardState.initial();
    }

    final stepName = draft["step"] as String?;
    final step = SetupWizardStep.values.firstWhere(
      (s) => s.name == stepName,
      orElse: () => SetupWizardStep.welcome,
    );

    final pathways = (draft["pathways"] as List?)?.cast<String>() ?? const <String>[];
    final recipientsRaw = (draft["recipients"] as List?) ?? const [];
    final recipients = recipientsRaw
        .whereType<Map>()
        .map((e) => RecipientDraft.fromMap(e.cast<String, dynamic>()))
        .toList();

    return SetupWizardState(
      step: step,
      selectedPathwayIds: pathways.toSet(),
      householdName: draft["householdName"] as String? ?? "",
      householdDescription: draft["householdDescription"] as String? ?? "",
      recipients: recipients.isEmpty
          ? SetupWizardState.initial().recipients
          : recipients,
      inviteEmails: (draft["inviteEmails"] as List?)?.cast<String>() ?? const [],
      inviteEmailInput: "",
      avatarIndex: (draft["avatarIndex"] as num?)?.toInt() ?? 1,
    );
  }

  final SetupWizardStep step;
  final Set<String> selectedPathwayIds;
  final String householdName;
  final String householdDescription;
  final List<RecipientDraft> recipients;
  final List<String> inviteEmails;
  final String inviteEmailInput;
  final int avatarIndex;
  final bool isSubmitting;
  final String? errorMessage;

  Map<String, dynamic> toDraftMap() {
    return {
      "step": step.name,
      "pathways": selectedPathwayIds.toList(),
      "householdName": householdName,
      "householdDescription": householdDescription,
      "recipients": recipients.map((e) => e.toMap()).toList(),
      "inviteEmails": inviteEmails,
      "avatarIndex": avatarIndex,
    };
  }

  SetupWizardState copyWith({
    SetupWizardStep? step,
    Set<String>? selectedPathwayIds,
    String? householdName,
    String? householdDescription,
    List<RecipientDraft>? recipients,
    List<String>? inviteEmails,
    String? inviteEmailInput,
    int? avatarIndex,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SetupWizardState(
      step: step ?? this.step,
      selectedPathwayIds: selectedPathwayIds ?? this.selectedPathwayIds,
      householdName: householdName ?? this.householdName,
      householdDescription: householdDescription ?? this.householdDescription,
      recipients: recipients ?? this.recipients,
      inviteEmails: inviteEmails ?? this.inviteEmails,
      inviteEmailInput: inviteEmailInput ?? this.inviteEmailInput,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        step,
        selectedPathwayIds,
        householdName,
        householdDescription,
        recipients,
        inviteEmails,
        inviteEmailInput,
        avatarIndex,
        isSubmitting,
        errorMessage,
      ];
}
