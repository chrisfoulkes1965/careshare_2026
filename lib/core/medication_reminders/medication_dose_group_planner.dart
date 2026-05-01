import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:timezone/timezone.dart" as tz;

import "../../features/medications/models/care_group_medication.dart";
import "medication_quiet_hours.dart";

/// A single grouped local notification.
final class DoseNudge {
  DoseNudge({
    required this.notificationId,
    required this.payload,
    required this.scheduledDate,
    required this.dateTimeMatch,
    required this.body,
  });

  final int notificationId;
  final String payload;
  final tz.TZDateTime scheduledDate;
  final DateTimeComponents? dateTimeMatch;
  final String body;
}

int doseNudgeHashId(String careGroupId, String groupKey) {
  return 4200000 + (Object.hash(careGroupId, groupKey).abs() % 500000);
}

String _bodyFor(List<String> names) {
  if (names.isEmpty) {
    return "Medication";
  }
  if (names.length == 1) {
    return "Time to take: ${names.first}";
  }
  const maxC = 180;
  final s = "Time to take: ${names.join(", ")}";
  return s.length <= maxC ? s : "${s.substring(0, maxC - 3)}...";
}

int _toDartW(int pluginDay) {
  if (pluginDay == 1) {
    return DateTime.sunday;
  }
  return pluginDay - 1;
}

tz.TZDateTime? _nextWeekly(int pluginDay, int hour, int minute) {
  final want = _toDartW(pluginDay);
  final now = tz.TZDateTime.now(tz.local);
  for (var add = 0; add < 8; add++) {
    final d = now.add(Duration(days: add));
    var candidate = tz.TZDateTime(
      tz.local,
      d.year,
      d.month,
      d.day,
      hour,
      minute,
    );
    if (candidate.weekday == want && candidate.isAfter(now)) {
      return candidate;
    }
  }
  return null;
}

tz.TZDateTime? _nextMonthly(int dom, int hour, int minute) {
  final now = tz.TZDateTime.now(tz.local);
  for (var add = 0; add < 400; add++) {
    final d = now.add(Duration(days: add));
    if (d.day != dom) {
      continue;
    }
    var candidate = tz.TZDateTime(
      tz.local,
      d.year,
      d.month,
      d.day,
      hour,
      minute,
    );
    if (candidate.isAfter(now)) {
      return candidate;
    }
  }
  return null;
}

tz.TZDateTime _nextDailyTime(int hour, int minute) {
  final now = tz.TZDateTime.now(tz.local);
  var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!d.isAfter(now)) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

String _pay(String careGroupId, Set<String> ids) {
  final s = ids.toList()..sort();
  return "dose|$careGroupId|${s.join(",")}";
}

List<DoseNudge> buildDoseNudges({
  required String careGroupId,
  required List<CareGroupMedication> meds,
  required bool isWindows,
  int? quietHoursStartMinute,
  int? quietHoursEndMinute,
}) {
  DateTimeComponents? nullOnWin(DateTimeComponents? x) {
    if (x == null) {
      return null;
    }
    return isWindows ? null : x;
  }
  final out = <DoseNudge>[];
  void add({
    required String gk,
    required Set<String> idSet,
    required List<String> nameList,
    required tz.TZDateTime when,
    required DateTimeComponents? match,
  }) {
    if (idSet.isEmpty) {
      return;
    }
    final adjusted = adjustAwayFromQuietHours(
      when,
      quietHoursStartMinute: quietHoursStartMinute,
      quietHoursEndMinute: quietHoursEndMinute,
    );
    out.add(
      DoseNudge(
        notificationId: doseNudgeHashId(careGroupId, gk),
        payload: _pay(careGroupId, idSet),
        scheduledDate: adjusted,
        dateTimeMatch: nullOnWin(match),
        body: _bodyFor(nameList),
      ),
    );
  }
  final track = meds
      .where(
        (e) =>
            e.reminderEnabled &&
            e.name.isNotEmpty &&
            e.hasValidReminderSchedule &&
            e.reminderTimes.isNotEmpty,
      )
      .toList();
  if (track.isEmpty) {
    return out;
  }
  final idToName = {for (final me in track) me.id: me.name};

  // Daily: group by time-of-day
  final dailyMap = <String, Set<String>>{};
  for (final med in track) {
    if (med.scheduleType != MedicationScheduleType.daily) {
      continue;
    }
    for (final t in med.reminderTimes) {
      final k = "d|${t.hour}|${t.minute}";
      dailyMap.putIfAbsent(k, () => <String>{}).add(med.id);
    }
  }
  for (final e in dailyMap.entries) {
    final parts = e.key.split("|");
    final h = int.parse(parts[1]);
    final min = int.parse(parts[2]);
    final when = _nextDailyTime(h, min);
    final idSet = e.value;
    final names = idSet.map((i) => idToName[i] ?? "").where((n) => n.isNotEmpty).toList()..sort();
    add(
      gk: e.key,
      idSet: idSet,
      nameList: names,
      when: when,
      match: DateTimeComponents.time,
    );
  }

  // Weekly
  final weekMap = <String, Set<String>>{};
  for (final med in track) {
    if (med.scheduleType != MedicationScheduleType.weekly) {
      continue;
    }
    for (final w in med.scheduleWeekdays) {
      for (final t in med.reminderTimes) {
        final k = "w|$w|${t.hour}|${t.minute}";
        weekMap.putIfAbsent(k, () => <String>{}).add(med.id);
      }
    }
  }
  for (final e in weekMap.entries) {
    final p = e.key.split("|");
    final w = int.parse(p[1]);
    final h = int.parse(p[2]);
    final min = int.parse(p[3]);
    final wh = _nextWeekly(w, h, min);
    if (wh == null) {
      continue;
    }
    final idSet = e.value;
    final names = idSet.map((i) => idToName[i] ?? "").where((n) => n.isNotEmpty).toList()..sort();
    add(
      gk: e.key,
      idSet: idSet,
      nameList: names,
      when: wh,
      match: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  // Monthly
  final monthMap = <String, Set<String>>{};
  for (final med in track) {
    if (med.scheduleType != MedicationScheduleType.monthly) {
      continue;
    }
    for (final dom in med.scheduleMonthDays) {
      for (final t in med.reminderTimes) {
        final k = "m|$dom|${t.hour}|${t.minute}";
        monthMap.putIfAbsent(k, () => <String>{}).add(med.id);
      }
    }
  }
  for (final e in monthMap.entries) {
    final p = e.key.split("|");
    final dom = int.parse(p[1]);
    final h = int.parse(p[2]);
    final min = int.parse(p[3]);
    final wh = _nextMonthly(dom, h, min);
    if (wh == null) {
      continue;
    }
    final idSet = e.value;
    final names = idSet.map((i) => idToName[i] ?? "").where((n) => n.isNotEmpty).toList()..sort();
    add(
      gk: e.key,
      idSet: idSet,
      nameList: names,
      when: wh,
      match: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  return out;
}
