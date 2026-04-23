import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:flutter_timezone/flutter_timezone.dart";
import "package:timezone/data/latest_all.dart" as tz_data;
import "package:timezone/timezone.dart" as tz;

import "../../features/medications/models/household_medication.dart";

/// Schedules local reminders to take medications (not available on web).
final class MedicationNotificationService {
  MedicationNotificationService._();
  static final MedicationNotificationService instance = MedicationNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _lastHouseholdId;
  List<HouseholdMedication> _lastMeds = const [];

  static const int _idBase = 5000000;
  static const String _channelId = "careshare_medications";
  static const String _channelName = "Medication reminders";

  Future<void> init() async {
    if (kIsWeb) {
      _ready = true;
      return;
    }
    try {
      tz_data.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      final name = zone.identifier;
      if (name.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(name));
      }
    } catch (e) {
      debugPrint("MedicationNotificationService timezone: $e");
    }

    const android = AndroidInitializationSettings("@mipmap/ic_launcher");
    const darwin = DarwinInitializationSettings();
    const win = WindowsInitializationSettings(
      appName: "CareShare",
      appUserModelId: "CareShare.CareShare",
      guid: "a1b2c3d4-5e6f-4a5b-8c9d-0e1f2a3b4c5d",
    );
    const linux = LinuxInitializationSettings(defaultActionName: "Open");
    const init = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: win,
      linux: linux,
    );
    await _plugin.initialize(settings: init);

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _ready = true;
  }

  /// Call when app returns to foreground so Windows can reschedule one-shot alerts.
  Future<void> onAppResumed() async {
    if (kIsWeb || !_ready) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final hid = _lastHouseholdId;
      if (hid != null && _lastMeds.isNotEmpty) {
        await syncMedications(hid, _lastMeds);
      }
    }
  }

  Future<void> cancelAll() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint("cancelAll: $e");
    }
    _lastHouseholdId = null;
    _lastMeds = const [];
  }

  Future<void> syncMedications(String householdId, List<HouseholdMedication> meds) async {
    if (kIsWeb || !_ready) {
      return;
    }

    _lastHouseholdId = householdId;
    _lastMeds = List<HouseholdMedication>.from(meds);

    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint("cancel before sync: $e");
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: "Reminders to take prescribed medicine",
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      windows: WindowsNotificationDetails(),
    );

    for (final m in meds) {
      if (!m.reminderEnabled || m.name.isEmpty) {
        continue;
      }
      for (var i = 0; i < m.reminderTimes.length; i++) {
        final time = m.reminderTimes[i];
        final id = _notificationId(m.id, i);
        final body = m.dosage.isNotEmpty ? "${m.name} (${m.dosage})" : m.name;
        final scheduled = _nextTzDateTime(time.hour, time.minute);
        final isWin = defaultTargetPlatform == TargetPlatform.windows;
        try {
          if (defaultTargetPlatform == TargetPlatform.linux) {
            continue;
          }
          await _plugin.zonedSchedule(
            id: id,
            title: "Medication",
            body: "Time to take: $body",
            scheduledDate: scheduled,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: isWin ? null : DateTimeComponents.time,
          );
        } catch (e, st) {
          debugPrint("schedule med $id: $e\n$st");
        }
      }
    }
  }

  int _notificationId(String medicationId, int slot) {
    return _idBase + (Object.hash(medicationId, slot).abs() % 800000);
  }

  tz.TZDateTime _nextTzDateTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
