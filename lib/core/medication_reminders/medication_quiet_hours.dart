import "package:timezone/timezone.dart" as tz;

bool _minuteInQuietWindow(int minuteOfDay, int startMin, int endMin) {
  if (startMin == endMin) {
    return false;
  }
  if (startMin < endMin) {
    return minuteOfDay >= startMin && minuteOfDay < endMin;
  }
  return minuteOfDay >= startMin || minuteOfDay < endMin;
}

/// Shifts [when] forward until it falls outside [quietHoursStartMinute]–[quietHoursEndMinute] (local TZ).
/// Both endpoints are minutes 0–1439; overnight windows supported (e.g. 22:00–07:00).
tz.TZDateTime adjustAwayFromQuietHours(
  tz.TZDateTime when, {
  int? quietHoursStartMinute,
  int? quietHoursEndMinute,
}) {
  final s = quietHoursStartMinute;
  final e = quietHoursEndMinute;
  if (s == null || e == null || s == e) {
    return when;
  }
  var cur = when;
  for (var i = 0; i < 2880; i++) {
    final m = cur.hour * 60 + cur.minute;
    if (!_minuteInQuietWindow(m, s, e)) {
      return cur;
    }
    cur = cur.add(const Duration(minutes: 1));
  }
  return when;
}
