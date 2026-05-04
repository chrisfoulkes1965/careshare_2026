import "package:equatable/equatable.dart";

import "../../user/models/home_sections_visibility.dart";

/// A care group the user belongs to, discovered via `careGroups/{id}/members/{uid}`.
/// [dataCareGroupId] is the document id where shared data under [careGroups] subcollections
/// live: same as [careGroupId] for a single merged document, or the linked id when a
/// `careGroupId` field points at another `careGroups` document.
final class CareGroupOption extends Equatable {
  const CareGroupOption({
    required this.careGroupId,
    required this.dataCareGroupId,
    required this.displayName,
    this.roles = const [],
    this.themeColor,
    this.homepageSectionsPolicy,
    this.photoUrl,
  });

  final String careGroupId;
  final String dataCareGroupId;
  final String displayName;

  /// From `careGroups/{id}/members/{uid}.roles` when the user is listed in that group.
  final List<String> roles;

  bool get isPrincipalCarer => roles.contains("principal_carer");

  /// Delegated administrative access (organiser) — overlaps with principal for group ops in rules/UI.
  bool get isCareGroupAdministrator =>
      roles.contains("care_group_administrator");

  /// Organisation access: invitations, member roles, off-app recipients (principal or administrator).
  bool get canManageCareGroupOrganisation =>
      isPrincipalCarer || isCareGroupAdministrator;

  /// Name, theme colour, shared calendar, and homepage section caps on the care group.
  /// Only [care_group_administrator] may change these (see Firestore rules).
  bool get canEditCareGroupNameThemeAndCalendar => isCareGroupAdministrator;

  /// Firestore: principal / POA / group admin may create or edit prescription fields on medications.
  bool get canConfigureMedicationPrescriptions =>
      roles.contains("principal_carer") ||
      roles.contains("power_of_attorney") ||
      roles.contains("care_group_administrator");

  /// Quiet hours & reorder windows live on `careGroups/{dataId}` — principal or group admin only (not POA).
  bool get canEditMedicationGroupSettings =>
      roles.contains("principal_carer") ||
      roles.contains("care_group_administrator");

  /// Optional `careGroups/{id}.themeColor` (ARGB int) for the home theme (header + page).
  final int? themeColor;

  /// Optional caps from `careGroups/{dataCareGroupId}.homepageSectionsPolicy`.
  /// Null means no group-level restriction (members follow their own preferences).
  final HomeSectionsVisibility? homepageSectionsPolicy;

  /// Optional `careGroups/{dataCareGroupId}.photoUrl` — shown as the care group avatar on home.
  final String? photoUrl;

  @override
  List<Object?> get props => [
        careGroupId,
        dataCareGroupId,
        displayName,
        roles,
        themeColor,
        homepageSectionsPolicy,
        photoUrl,
      ];
}
