import "package:flutter_bloc/flutter_bloc.dart";

import "../../auth/bloc/auth_bloc.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../user/models/user_profile.dart";
import "../models/setup_models.dart";
import "../repository/setup_repository.dart";
import "setup_wizard_event.dart";
import "setup_wizard_state.dart";

final class SetupWizardBloc extends Bloc<SetupWizardEvent, SetupWizardState> {
  SetupWizardBloc({
    required UserProfile profile,
    required AuthBloc authBloc,
    required ProfileCubit profileCubit,
    required SetupRepository setupRepository,
  })  : _authBloc = authBloc,
        _profileCubit = profileCubit,
        _setupRepository = setupRepository,
        super(SetupWizardState.fromProfile(profile)) {
    on<SetupWizardNextPressed>(_onNext);
    on<SetupWizardBackPressed>(_onBack);
    on<SetupWizardPathwayToggled>(_onPathwayToggled);
    on<SetupWizardCareGroupNameChanged>(_onCareGroupName);
    on<SetupWizardCareGroupDescriptionChanged>(_onCareGroupDescription);
    on<SetupWizardAddressChanged>(_onAddress);
    on<SetupWizardAddressTypeChanged>(_onAddressType);
    on<SetupWizardCaredForMyselfToggled>(_onCaredForMyselfToggled);
    on<SetupWizardRecipientNameChanged>(_onRecipientName);
    on<SetupWizardRecipientAccessChanged>(_onRecipientAccess);
    on<SetupWizardRecipientAdded>(_onRecipientAdded);
    on<SetupWizardRecipientRemoved>(_onRecipientRemoved);
    on<SetupWizardInviteInputChanged>(_onInviteInput);
    on<SetupWizardInviteAdded>(_onInviteAdded);
    on<SetupWizardInviteRemoved>(_onInviteRemoved);
    on<SetupWizardAvatarSelected>(_onAvatarSelected);
    on<SetupWizardSubmitted>(_onSubmitted);
  }

  final AuthBloc _authBloc;
  final ProfileCubit _profileCubit;
  final SetupRepository _setupRepository;

  Future<void> _persistDraft(SetupWizardState s) async {
    final uid = _authBloc.state.user?.uid;
    if (uid == null || !_setupRepository.isAvailable) return;
    await _setupRepository.saveDraft(uid, s.toDraftMap());
  }

  Future<void> _onNext(SetupWizardNextPressed event, Emitter<SetupWizardState> emit) async {
    final s = state;
    final err = _validateForStep(s);
    if (err != null) {
      emit(s.copyWith(errorMessage: err, clearError: false));
      return;
    }

    emit(s.copyWith(clearError: true));
    if (s.step == SetupWizardStep.summary) {
      return;
    }

    final next = SetupWizardStep.values[s.step.index + 1];
    final updated = s.copyWith(step: next, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onBack(SetupWizardBackPressed event, Emitter<SetupWizardState> emit) async {
    if (state.step == SetupWizardStep.welcome) return;
    final prev = SetupWizardStep.values[state.step.index - 1];
    final updated = state.copyWith(step: prev, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onPathwayToggled(
    SetupWizardPathwayToggled event,
    Emitter<SetupWizardState> emit,
  ) async {
    final next = Set<String>.from(state.selectedPathwayIds);
    if (next.contains(event.pathwayId)) {
      next.remove(event.pathwayId);
    } else {
      next.add(event.pathwayId);
    }
    final updated = state.copyWith(selectedPathwayIds: next, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onCareGroupName(
    SetupWizardCareGroupNameChanged event,
    Emitter<SetupWizardState> emit,
  ) async {
    final updated = state.copyWith(careGroupName: event.value, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onCareGroupDescription(
    SetupWizardCareGroupDescriptionChanged event,
    Emitter<SetupWizardState> emit,
  ) async {
    final updated = state.copyWith(careGroupDescription: event.value, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onAddress(SetupWizardAddressChanged event, Emitter<SetupWizardState> emit) async {
    final updated = state.copyWith(address: event.value, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onAddressType(SetupWizardAddressTypeChanged event, Emitter<SetupWizardState> emit) async {
    final updated = state.copyWith(addressType: event.value, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  String _defaultSelfDisplayName() {
    return _authBloc.state.user?.displayName?.trim().isNotEmpty == true
        ? _authBloc.state.user!.displayName!.trim()
        : (_authBloc.state.user?.email?.split("@").first ?? "Me");
  }

  Future<void> _onCaredForMyselfToggled(
    SetupWizardCaredForMyselfToggled event,
    Emitter<SetupWizardState> emit,
  ) async {
    if (event.enabled) {
      if (state.recipients.any((r) => r.isSelf)) {
        return;
      }
      final withSelf = [
        RecipientDraft(
          id: kSelfRecipientId,
          displayName: _defaultSelfDisplayName(),
          accessMode: RecipientAccessMode.managed,
          isSelf: true,
        ),
        ...state.recipients,
      ];
      final updated = state.copyWith(recipients: withSelf, clearError: true);
      emit(updated);
      await _persistDraft(updated);
    } else {
      final list = state.recipients.where((r) => !r.isSelf).toList();
      final updated = state.copyWith(recipients: list, clearError: true);
      emit(updated);
      await _persistDraft(updated);
    }
  }

  Future<void> _onRecipientName(
    SetupWizardRecipientNameChanged event,
    Emitter<SetupWizardState> emit,
  ) async {
    final list = state.recipients
        .map(
          (r) => r.id == event.id
              ? RecipientDraft(
                  id: r.id,
                  displayName: event.name,
                  accessMode: r.accessMode,
                  isSelf: r.isSelf,
                )
              : r,
        )
        .toList();
    final updated = state.copyWith(recipients: list, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onRecipientAccess(
    SetupWizardRecipientAccessChanged event,
    Emitter<SetupWizardState> emit,
  ) async {
    final list = state.recipients
        .map(
          (r) => r.id == event.id
              ? RecipientDraft(
                  id: r.id,
                  displayName: r.displayName,
                  accessMode: event.mode,
                  isSelf: r.isSelf,
                )
              : r,
        )
        .toList();
    final updated = state.copyWith(recipients: list, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onRecipientAdded(
    SetupWizardRecipientAdded event,
    Emitter<SetupWizardState> emit,
  ) async {
    final updatedList = [
      ...state.recipients,
      RecipientDraft(
        id: newRecipientId(),
        displayName: "",
        accessMode: RecipientAccessMode.managed,
        isSelf: false,
      ),
    ];
    final updated = state.copyWith(recipients: updatedList, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onRecipientRemoved(
    SetupWizardRecipientRemoved event,
    Emitter<SetupWizardState> emit,
  ) async {
    final matches = state.recipients.where((r) => r.id == event.id);
    if (matches.isEmpty) return;
    if (matches.first.isSelf) return;
    final updatedList = state.recipients.where((r) => r.id != event.id).toList();
    final updated = state.copyWith(recipients: updatedList, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  void _onInviteInput(SetupWizardInviteInputChanged event, Emitter<SetupWizardState> emit) {
    emit(state.copyWith(inviteEmailInput: event.value, clearError: true));
  }

  Future<void> _onInviteAdded(SetupWizardInviteAdded event, Emitter<SetupWizardState> emit) async {
    final raw = state.inviteEmailInput.trim();
    if (!raw.contains("@")) {
      emit(state.copyWith(errorMessage: "Enter a valid email."));
      return;
    }
    final email = raw.toLowerCase();
    final self = _authBloc.state.user?.email?.toLowerCase();
    if (self != null && email == self) {
      emit(state.copyWith(errorMessage: "You are already in this group."));
      return;
    }
    if (state.inviteEmails.contains(email)) {
      emit(state.copyWith(inviteEmailInput: "", clearError: true));
      return;
    }
    final updated = state.copyWith(
      inviteEmails: [...state.inviteEmails, email],
      inviteEmailInput: "",
      clearError: true,
    );
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onInviteRemoved(
    SetupWizardInviteRemoved event,
    Emitter<SetupWizardState> emit,
  ) async {
    final updated = state.copyWith(
      inviteEmails: state.inviteEmails.where((e) => e != event.email).toList(),
      clearError: true,
    );
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onAvatarSelected(
    SetupWizardAvatarSelected event,
    Emitter<SetupWizardState> emit,
  ) async {
    final updated = state.copyWith(avatarIndex: event.index, clearError: true);
    emit(updated);
    await _persistDraft(updated);
  }

  Future<void> _onSubmitted(SetupWizardSubmitted event, Emitter<SetupWizardState> emit) async {
    final uid = _authBloc.state.user?.uid;
    if (uid == null) return;
    if (!_setupRepository.isAvailable) {
      emit(state.copyWith(errorMessage: "Firebase is not configured."));
      return;
    }

    final err = _validateForStep(state, includeSummary: true);
    if (err != null) {
      emit(state.copyWith(errorMessage: err));
      return;
    }

    emit(state.copyWith(isSubmitting: true, clearError: true));
    try {
      final principalName = _authBloc.state.user?.displayName ??
          _authBloc.state.user?.email?.split("@").first ??
          "Principal carer";

      await _setupRepository.completeWizard(
        uid: uid,
        submit: SetupSubmit(
          careGroupName: state.careGroupName.trim(),
          careGroupDescription: state.careGroupDescription.trim(),
          pathwayIds: state.selectedPathwayIds.toList(),
          recipients: state.recipients
              .map(
                (r) => RecipientDraft(
                  id: r.id,
                  displayName: r.displayName.trim(),
                  accessMode: r.accessMode,
                  isSelf: r.isSelf,
                ),
              )
              .toList(),
          address: state.address.trim(),
          addressType: state.addressType,
          inviteEmails: state.inviteEmails,
          avatarIndex: state.avatarIndex,
          principalDisplayName: principalName,
        ),
      );
      await _profileCubit.refresh();
      emit(state.copyWith(isSubmitting: false));
    } catch (e) {
      final raw = e.toString();
      final friendly = raw.contains("permission-denied") || raw.contains("PERMISSION_DENIED")
          ? "Could not save your care group (Firestore permission denied). "
              "Deploy the latest firebase/firestore.rules to your project, then try again."
          : raw;
      emit(state.copyWith(isSubmitting: false, errorMessage: friendly));
    }
  }

  bool _hasValidCaredFor(SetupWizardState s) {
    for (final r in s.recipients) {
      if (r.displayName.trim().isNotEmpty) return true;
    }
    return false;
  }

  String? _validateForStep(SetupWizardState s, {bool includeSummary = false}) {
    switch (s.step) {
      case SetupWizardStep.welcome:
        return null;
      case SetupWizardStep.caredFor:
        if (s.recipients.isEmpty) {
          return "Add who is being cared for, or choose “Myself”.";
        }
        if (!_hasValidCaredFor(s)) {
          return "Enter a name for each person listed (including yourself if selected).";
        }
        return null;
      case SetupWizardStep.location:
        if (s.address.trim().isEmpty) {
          return "Enter the address for this care group.";
        }
        return null;
      case SetupWizardStep.pathways:
        if (s.selectedPathwayIds.isEmpty) {
          return "Choose at least one care pathway.";
        }
        return null;
      case SetupWizardStep.careGroup:
        if (s.careGroupName.trim().isEmpty) {
          return "Name your care group.";
        }
        return null;
      case SetupWizardStep.invites:
      case SetupWizardStep.avatar:
        return null;
      case SetupWizardStep.summary:
        if (!includeSummary) return null;
        if (!_hasValidCaredFor(s)) {
          return "Enter a name for each person listed (including yourself if selected).";
        }
        if (s.address.trim().isEmpty) return "Enter the address for this care group.";
        if (s.selectedPathwayIds.isEmpty) return "Choose at least one care pathway.";
        if (s.careGroupName.trim().isEmpty) return "Name your care group.";
        return null;
    }
  }
}
