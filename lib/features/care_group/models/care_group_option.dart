import "package:equatable/equatable.dart";

/// A care group the user belongs to, discovered via `careGroups/{id}/members/{uid}`.
/// [householdId] is the linked home document id (Firestore field on the care group doc is often `careGroupId`).
final class CareGroupOption extends Equatable {
  const CareGroupOption({
    required this.careGroupId,
    required this.householdId,
    required this.displayName,
    this.roles = const [],
  });

  final String careGroupId;
  final String householdId;
  final String displayName;

  /// From `careGroups/{id}/members/{uid}.roles` when the user is listed in that group.
  final List<String> roles;

  @override
  List<Object?> get props => [careGroupId, householdId, displayName, roles];
}
