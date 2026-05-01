import "dart:convert";

import "package:crypto/crypto.dart";
import "package:timezone/timezone.dart" as tz;

/// Stable id for `careGroups/.../medicationReminderAcks/{id}` (matches Cloud Functions).
String medicationReminderAckDocId({
  required String careGroupDataId,
  required String slotKey,
  required List<String> medicationIds,
}) {
  final ids = [...medicationIds]..sort();
  final raw = "$careGroupDataId|$slotKey|${ids.join(",")}";
  final digest = sha256.convert(utf8.encode(raw));
  return digest.toString().substring(0, 40);
}

/// Wall-clock key for the quiet-adjusted reminder instant (must match JS scheduler).
String doseSlotKeyFromTz(tz.TZDateTime t) {
  final mo = t.month.toString().padLeft(2, "0");
  final d = t.day.toString().padLeft(2, "0");
  final mi = t.minute.toString().padLeft(2, "0");
  return "${t.year}-$mo-${d}_t_${t.hour}_$mi";
}
