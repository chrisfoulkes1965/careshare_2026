/// `careGroups/{careGroupId}` — inventory / reorder (stored on the care group document).
final class MedicationInventoryCareGroupSettings {
  const MedicationInventoryCareGroupSettings({
    this.reorderLeadDays = 7,
    this.reorderWindowDays = 14,
    this.quietHoursStartMinute,
    this.quietHoursEndMinute,
  });

  static const int defaultLeadDays = 7;
  static const int defaultWindowDays = 14;

  final int reorderLeadDays;
  final int reorderWindowDays;

  /// Minutes from midnight (0–1439), local device timezone when scheduling. Both null = off.
  final int? quietHoursStartMinute;
  final int? quietHoursEndMinute;

  bool get quietHoursEnabled =>
      quietHoursStartMinute != null &&
      quietHoursEndMinute != null &&
      quietHoursStartMinute != quietHoursEndMinute;

  static MedicationInventoryCareGroupSettings fromData(Map<String, dynamic>? d) {
    if (d == null) {
      return const MedicationInventoryCareGroupSettings();
    }
    final qs = _parseMinute(d["medicationQuietHoursStartMinute"] ?? d["quietHoursStartMinute"]);
    final qe = _parseMinute(d["medicationQuietHoursEndMinute"] ?? d["quietHoursEndMinute"]);
    return MedicationInventoryCareGroupSettings(
      reorderLeadDays: _clampDay(d["medicationReorderLeadDays"] ?? d["reorderLeadDays"], defaultLeadDays).clamp(0, 90),
      reorderWindowDays: _clampDay(
        d["medicationReorderWindowDays"] ?? d["reorderWindowDays"],
        defaultWindowDays,
      ).clamp(0, 180),
      quietHoursStartMinute: qs,
      quietHoursEndMinute: qe,
    );
  }

  static int? _parseMinute(Object? v) {
    if (v == null) {
      return null;
    }
    var n = 0;
    if (v is int) {
      n = v;
    } else if (v is num) {
      n = v.toInt();
    } else {
      return null;
    }
    return n.clamp(0, 1439);
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
    final m = <String, dynamic>{
      "medicationReorderLeadDays": reorderLeadDays,
      "medicationReorderWindowDays": reorderWindowDays,
    };
    if (quietHoursEnabled) {
      m["medicationQuietHoursStartMinute"] = quietHoursStartMinute;
      m["medicationQuietHoursEndMinute"] = quietHoursEndMinute;
    } else {
      m["medicationQuietHoursStartMinute"] = null;
      m["medicationQuietHoursEndMinute"] = null;
    }
    return m;
  }
}
