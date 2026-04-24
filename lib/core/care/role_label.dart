/// Human-friendly label for a role string stored in Firestore.
String careGroupRoleLabel(String role) {
  return switch (role) {
    "principal_carer" => "Principal carer",
    "carer" => "Carer",
    "financial_manager" => "Financial",
    "power_of_attorney" => "Power of attorney",
    "receives_care" => "Receives care",
    _ => role.replaceAll("_", " "),
  };
}
