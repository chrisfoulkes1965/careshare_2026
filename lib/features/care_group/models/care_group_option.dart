import "package:equatable/equatable.dart";

/// A care group (and linked home) the user can work in, discovered via `members/{uid}`.
/// [householdId] is the `households/{id}` document for shared data; [careGroupId] is `careGroups/{id}`.
final class CareGroupOption extends Equatable {
  const CareGroupOption({
    required this.householdId,
    required this.careGroupId,
    required this.displayName,
  });

  final String householdId;
  final String careGroupId;
  final String displayName;

  @override
  List<Object?> get props => [householdId, careGroupId, displayName];
}
