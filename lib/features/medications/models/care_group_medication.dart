import "package:cloud_firestore/cloud_firestore.dart";

/// How [reminderTimes] are interpreted (local device notifications; see [CareGroupMedication]).
enum MedicationScheduleType {
  /// Every day at each of [reminderTimes].
  daily,

  /// On each selected weekday (1=Sun .. 7=Sat, NLM [Day] style) at each of [reminderTimes].
  weekly,

  /// On each calendar [scheduleMonthDays] of the month (1–31) at each of [reminderTimes].
  monthly,
}

/// One document under `careGroups/{cid}/medications/{id}`.
final class CareGroupMedication {
  const CareGroupMedication({
    required this.id,
    required this.name,
    this.careRecipientId,
    this.medicationForm = "",
    this.dosage = "",
    this.instructions = "",
    this.notes = "",
    this.photoUrl,
    this.reminderEnabled = false,
    this.reminderTimes = const [],
    this.scheduleType = MedicationScheduleType.daily,
    this.scheduleWeekdays = const [],
    this.scheduleMonthDays = const [],
    this.quantityOnHand,
    this.lowStockThreshold,
    this.lastStockDate,
  });

  final String id;
  final String name;

  /// [CareGroupMember.userId] of the person this medication is for (matches `recipientProfiles` or `members/`).
  final String? careRecipientId;

  /// e.g. tablet, liquid, injection — from packaging (optional).
  final String medicationForm;
  final String dosage;
  final String instructions;
  final String notes;
  final String? photoUrl;
  final bool reminderEnabled;
  final List<MedicationReminderTime> reminderTimes;
  final MedicationScheduleType scheduleType;

  /// Weekdays 1=Sunday … 7=Saturday (matches [flutter_local_notifications] [Day]).
  final List<int> scheduleWeekdays;
  final List<int> scheduleMonthDays;

  /// Doses remaining; `null` means not set — treat as [dosesIn28DayPeriod] for planning.
  final int? quantityOnHand;

  /// Alert when [quantityOnHand] is at or below this (requires both set).
  final int? lowStockThreshold;

  /// Last time on-hand stock was updated (stock take, dose deduction, or manual edit).
  final DateTime? lastStockDate;

  static CareGroupMedication fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    return fromMap(d.id, d.data());
  }

  static CareGroupMedication fromMap(String id, Map<String, dynamic> data) {
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
    final st = _parseScheduleType(data["reminderSchedule"]);
    final wds = _parseIntList(data["reminderWeekdays"], 1, 7);
    final mds = _parseIntList(data["reminderMonthDays"], 1, 31);
    final q = data["quantityOnHand"];
    int? qoh;
    if (q is int) {
      qoh = q;
    } else if (q is num) {
      qoh = q.toInt();
    }
    if (qoh != null) {
      qoh = qoh.clamp(0, 0x6fffffff);
    }
    final lst = data["lowStockThreshold"];
    int? lowStock;
    if (lst is int) {
      lowStock = lst.clamp(0, 0x6fffffff);
    } else     if (lst is num) {
      lowStock = lst.toInt().clamp(0, 0x6fffffff);
    }
    final lsd = data["lastStockDate"];
    DateTime? lastStock;
    if (lsd is Timestamp) {
      lastStock = lsd.toDate();
    }
    final cr = data["careRecipientId"];
    String? careRecipientId;
    if (cr is String && cr.trim().isNotEmpty) {
      careRecipientId = cr.trim();
    }
    return CareGroupMedication(
      id: id,
      name: (data["name"] as String?)?.trim() ?? "",
      careRecipientId: careRecipientId,
      medicationForm: (data["medicationForm"] as String?)?.trim() ?? "",
      dosage: (data["dosage"] as String?)?.trim() ?? "",
      instructions: (data["instructions"] as String?)?.trim() ?? "",
      notes: (data["notes"] as String?)?.trim() ?? "",
      photoUrl: (data["photoUrl"] as String?)?.trim(),
      reminderEnabled: data["reminderEnabled"] == true,
      reminderTimes: times,
      scheduleType: st,
      scheduleWeekdays: wds,
      scheduleMonthDays: mds,
      quantityOnHand: qoh,
      lowStockThreshold: lowStock,
      lastStockDate: lastStock,
    );
  }

  static MedicationScheduleType _parseScheduleType(Object? v) {
    if (v is! String) {
      return MedicationScheduleType.daily;
    }
    return switch (v) {
      "weekly" => MedicationScheduleType.weekly,
      "monthly" => MedicationScheduleType.monthly,
      _ => MedicationScheduleType.daily,
    };
  }

  static List<int> _parseIntList(Object? v, int min, int max) {
    if (v is! List) {
      return const [];
    }
    final out = <int>[];
    final seen = <int>{};
    for (final e in v) {
      var n = 0;
      if (e is int) {
        n = e;
      } else if (e is num) {
        n = e.toInt();
      } else {
        continue;
      }
      n = n.clamp(min, max);
      if (seen.add(n)) {
        out.add(n);
      }
    }
    out.sort();
    return out;
  }

  int get _scheduleSlotCount {
    switch (scheduleType) {
      case MedicationScheduleType.daily:
        return reminderTimes.length;
      case MedicationScheduleType.weekly:
        return scheduleWeekdays.length * reminderTimes.length;
      case MedicationScheduleType.monthly:
        return scheduleMonthDays.length * reminderTimes.length;
    }
  }

  /// One line for list tiles, e.g. "Daily 08:00" or "Weekly Mon,Wed 08:00".
  String get scheduleSummaryLine {
    if (!reminderEnabled) {
      return "";
    }
    if (reminderTimes.isEmpty) {
      return "Reminders on (add times in edit)";
    }
    const wnames = <String>["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    final timeStr = reminderTimes
        .map((t) => "${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}")
        .join(", ");
    return switch (scheduleType) {
      MedicationScheduleType.daily => "Daily: $timeStr",
      MedicationScheduleType.weekly => scheduleWeekdays.isEmpty
          ? "Weekly: pick days in edit"
          : "Weekly ${scheduleWeekdays.map((d) => d >= 1 && d <= 7 ? wnames[d - 1] : "?").join(", ")} — $timeStr",
      MedicationScheduleType.monthly => scheduleMonthDays.isEmpty
          ? "Monthly: pick days in edit"
          : "Monthly: days ${scheduleMonthDays.join(", ")} — $timeStr",
    };
  }

  static const int maxNotificationSlots = 64;

  /// Doses in the next 28 calendar days (used when [quantityOnHand] is not set).
  int dosesIn28DayPeriod() {
    if (reminderTimes.isEmpty) {
      return 0;
    }
    if (!reminderEnabled || !hasValidReminderSchedule) {
      return 0;
    }
    final now = DateTime.now();
    var total = 0;
    for (var i = 0; i < 28; i++) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      if (_occursOnCalendarDay(d)) {
        total += reminderTimes.length;
      }
    }
    return total;
  }

  /// Whether a dose is due on this calendar [day] (date only).
  bool _occursOnCalendarDay(DateTime day) {
    if (reminderTimes.isEmpty) {
      return false;
    }
    return switch (scheduleType) {
      MedicationScheduleType.daily => true,
      MedicationScheduleType.weekly => scheduleWeekdays.contains(_dartWeekdayToPluginDay(day.weekday)),
      MedicationScheduleType.monthly => scheduleMonthDays.contains(day.day),
    };
  }

  static int _dartWeekdayToPluginDay(int dartWeekday) {
    if (dartWeekday == DateTime.sunday) {
      return 1;
    }
    return dartWeekday + 1;
  }

  /// Assumed or entered doses in stock.
  int get effectiveDosesInHand {
    return quantityOnHand ?? dosesIn28DayPeriod();
  }

  /// Average scheduled doses per day (from the next-28-day window, same as [dosesIn28DayPeriod] / 28).
  double get avgDosesPerDay {
    if (!reminderEnabled || reminderTimes.isEmpty) {
      return 0;
    }
    if (!hasValidReminderSchedule) {
      return 0;
    }
    return dosesIn28DayPeriod() / 28.0;
  }

  /// Rough days until stock runs out (0 if no regular doses, infinity if no consumption).
  double? get estimatedDaysOfSupply {
    if (!reminderEnabled || reminderTimes.isEmpty || !hasValidReminderSchedule) {
      return null;
    }
    final perDay = avgDosesPerDay;
    if (perDay <= 0) {
      return null;
    }
    return effectiveDosesInHand / perDay;
  }

  /// One line, e.g. "≈ 12.5 d supply (42 doses) · entered"
  String get inventorySummaryLine {
    if (!reminderEnabled || reminderTimes.isEmpty) {
      return "";
    }
    if (!hasValidReminderSchedule) {
      return "Inventory: complete schedule to estimate supply";
    }
    final d = estimatedDaysOfSupply;
    if (d == null) {
      return "";
    }
    final source = quantityOnHand == null ? "assumed 28d default" : "on hand: ${quantityOnHand!} doses";
    var line = "≈ ${d.toStringAsFixed(1)} d supply — $source";
    if (lastStockDate != null) {
      final local = lastStockDate!.toLocal();
      final ds =
          "${local.year}-${local.month.toString().padLeft(2, "0")}-${local.day.toString().padLeft(2, "0")}";
      line += " · stock date $ds";
    }
    return line;
  }

  /// Whether this schedule is valid to enable reminders (enforced in UI; slot cap for OS limits).
  bool get hasValidReminderSchedule {
    if (!reminderEnabled) {
      return true;
    }
    if (reminderTimes.isEmpty) {
      return false;
    }
    return switch (scheduleType) {
      MedicationScheduleType.daily => true,
      MedicationScheduleType.weekly => scheduleWeekdays.isNotEmpty,
      MedicationScheduleType.monthly => scheduleMonthDays.isNotEmpty,
    } && _scheduleSlotCount > 0 && _scheduleSlotCount <= maxNotificationSlots;
  }

  /// True when an explicit count is at or below the configured threshold.
  bool get isLowStock {
    final q = quantityOnHand;
    final t = lowStockThreshold;
    if (q == null || t == null) {
      return false;
    }
    return q <= t;
  }
}

final class MedicationReminderTime {
  const MedicationReminderTime({required this.hour, required this.minute});

  final int hour;
  final int minute;

  Map<String, int> toMap() => {"h": hour, "m": minute};
}
