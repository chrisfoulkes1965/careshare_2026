import "package:cloud_firestore/cloud_firestore.dart";

/// One document under `households/{hid}/medications/{id}`.
final class HouseholdMedication {
  const HouseholdMedication({
    required this.id,
    required this.name,
    this.dosage = "",
    this.instructions = "",
    this.notes = "",
    this.photoUrl,
    this.reminderEnabled = false,
    this.reminderTimes = const [],
  });

  final String id;
  final String name;
  final String dosage;
  final String instructions;
  final String notes;
  final String? photoUrl;
  final bool reminderEnabled;
  final List<MedicationReminderTime> reminderTimes;

  static HouseholdMedication fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final raw = data["reminderTimes"];
    final times = <MedicationReminderTime>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final h = e["h"];
          final m = e["m"];
          if (h is int && m is int) {
            times.add(MedicationReminderTime(hour: h.clamp(0, 23), minute: m.clamp(0, 59)));
          } else if (h is num && m is num) {
            times.add(MedicationReminderTime(hour: h.toInt().clamp(0, 23), minute: m.toInt().clamp(0, 59)));
          }
        }
      }
    }
    return HouseholdMedication(
      id: d.id,
      name: (data["name"] as String?)?.trim() ?? "",
      dosage: (data["dosage"] as String?)?.trim() ?? "",
      instructions: (data["instructions"] as String?)?.trim() ?? "",
      notes: (data["notes"] as String?)?.trim() ?? "",
      photoUrl: (data["photoUrl"] as String?)?.trim(),
      reminderEnabled: data["reminderEnabled"] == true,
      reminderTimes: times,
    );
  }
}

final class MedicationReminderTime {
  const MedicationReminderTime({required this.hour, required this.minute});

  final int hour;
  final int minute;

  Map<String, int> toMap() => {"h": hour, "m": minute};
}
