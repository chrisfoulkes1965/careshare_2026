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
