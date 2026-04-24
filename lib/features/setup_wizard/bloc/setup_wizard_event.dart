import "package:equatable/equatable.dart";

import "../models/setup_models.dart" show CareAddressType, RecipientAccessMode;

sealed class SetupWizardEvent extends Equatable {
  const SetupWizardEvent();

  @override
  List<Object?> get props => [];
}

final class SetupWizardNextPressed extends SetupWizardEvent {
  const SetupWizardNextPressed();
}

final class SetupWizardBackPressed extends SetupWizardEvent {
  const SetupWizardBackPressed();
}

final class SetupWizardPathwayToggled extends SetupWizardEvent {
  const SetupWizardPathwayToggled(this.pathwayId);

  final String pathwayId;

  @override
  List<Object?> get props => [pathwayId];
}

final class SetupWizardCareGroupNameChanged extends SetupWizardEvent {
  const SetupWizardCareGroupNameChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

final class SetupWizardCareGroupDescriptionChanged extends SetupWizardEvent {
  const SetupWizardCareGroupDescriptionChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

final class SetupWizardAddressChanged extends SetupWizardEvent {
  const SetupWizardAddressChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

final class SetupWizardAddressTypeChanged extends SetupWizardEvent {
  const SetupWizardAddressTypeChanged(this.value);

  final CareAddressType value;

  @override
  List<Object?> get props => [value];
}

final class SetupWizardCaredForMyselfToggled extends SetupWizardEvent {
  const SetupWizardCaredForMyselfToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class SetupWizardRecipientNameChanged extends SetupWizardEvent {
  const SetupWizardRecipientNameChanged({required this.id, required this.name});

  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

final class SetupWizardRecipientAccessChanged extends SetupWizardEvent {
  const SetupWizardRecipientAccessChanged({required this.id, required this.mode});

  final String id;
  final RecipientAccessMode mode;

  @override
  List<Object?> get props => [id, mode];
}

final class SetupWizardRecipientAdded extends SetupWizardEvent {
  const SetupWizardRecipientAdded();
}

final class SetupWizardRecipientRemoved extends SetupWizardEvent {
  const SetupWizardRecipientRemoved(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class SetupWizardInviteInputChanged extends SetupWizardEvent {
  const SetupWizardInviteInputChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

final class SetupWizardInviteAdded extends SetupWizardEvent {
  const SetupWizardInviteAdded();
}

final class SetupWizardInviteRemoved extends SetupWizardEvent {
  const SetupWizardInviteRemoved(this.email);

  final String email;

  @override
  List<Object?> get props => [email];
}

final class SetupWizardAvatarSelected extends SetupWizardEvent {
  const SetupWizardAvatarSelected(this.index);

  final int index;

  @override
  List<Object?> get props => [index];
}

final class SetupWizardSubmitted extends SetupWizardEvent {
  const SetupWizardSubmitted();
}
