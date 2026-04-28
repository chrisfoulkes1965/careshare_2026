import "package:equatable/equatable.dart";

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
  });

  final String careGroupId;
  final String dataCareGroupId;
  final String displayName;

  /// From `careGroups/{id}/members/{uid}.roles` when the user is listed in that group.
  final List<String> roles;

  /// Optional `careGroups/{id}.themeColor` (ARGB int) for the home theme (header + page).
  final int? themeColor;

  bool get isPrincipalCarer => roles.contains("principal_carer");

  @override
  List<Object?> get props => [careGroupId, dataCareGroupId, displayName, roles, themeColor];
}
