/// Normalizes arbitrary role strings against [kAssignableCareGroupRoles]; defaults to [carer].
List<String> normalizeAssignableCareGroupRoles(List<String> raw) {
  final allow = Set<String>.from(kAssignableCareGroupRoles);
  final out = <String>[];
  for (final r in raw) {
    final t = r.trim();
    if (allow.contains(t) && !out.contains(t)) {
      out.add(t);
    }
  }
  return out.isEmpty ? const <String>["carer"] : out;
}

/// Roles the principal or care group administrator can assign on the members screen (display order).
const List<String> kAssignableCareGroupRoles = [
  "principal_carer",
  "care_group_administrator",
  "carer",
  "financial_manager",
  "power_of_attorney",
  "receives_care",
];

/// Human-friendly label for a role string stored in Firestore.
String careGroupRoleLabel(String role) {
  return switch (role) {
    "principal_carer" => "Principal carer",
    "care_group_administrator" => "Care group administrator",
    "carer" => "Carer",
    "financial_manager" => "Financial",
    "power_of_attorney" => "Power of attorney",
    "receives_care" => "Receives care",
    _ => role.replaceAll("_", " "),
  };
}
