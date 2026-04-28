/// `careGroups/{careGroupId}` — inventory / reorder (stored on the care group document).
final class MedicationInventoryCareGroupSettings {
  const MedicationInventoryCareGroupSettings({
    this.reorderLeadDays = 7,
    this.reorderWindowDays = 14,
  });

  static const int defaultLeadDays = 7;
  static const int defaultWindowDays = 14;

  final int reorderLeadDays;
  final int reorderWindowDays;

  static MedicationInventoryCareGroupSettings fromData(Map<String, dynamic>? d) {
    if (d == null) {
      return const MedicationInventoryCareGroupSettings();
    }
    return MedicationInventoryCareGroupSettings(
      reorderLeadDays: _clampDay(d["medicationReorderLeadDays"] ?? d["reorderLeadDays"], defaultLeadDays).clamp(0, 90),
      reorderWindowDays: _clampDay(
        d["medicationReorderWindowDays"] ?? d["reorderWindowDays"],
        defaultWindowDays,
      ).clamp(0, 180),
    );
  }

  static int _clampDay(Object? v, int fallback) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return fallback;
  }

  Map<String, dynamic> toMap() {
    return {
      "medicationReorderLeadDays": reorderLeadDays,
      "medicationReorderWindowDays": reorderWindowDays,
    };
  }
}
