/// [GoRouter] `extra` for [MedicationDoseConfirmScreen].
final class MedicationDoseRouteArgs {
  const MedicationDoseRouteArgs({
    required this.careGroupId,
    required this.medicationIds,
  });

  final String careGroupId;
  final List<String> medicationIds;
}
