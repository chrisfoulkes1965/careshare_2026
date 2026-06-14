import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:flutter_timezone/flutter_timezone.dart";
import "package:timezone/data/latest_all.dart" as tz_data;
import "package:timezone/timezone.dart" as tz;

import "medication_dose_group_planner.dart";
import "../../features/medications/models/care_group_medication.dart";
import "../../features/pill_box/logic/pill_box_refill_reminders.dart";

/// Grouped local reminders; tap opens a confirmation flow (set [setDosePayloadHandler] from [app.dart]).
/// Foreground FCM for chat also uses the same plugin (set [setChatPayloadHandler]).
final class MedicationNotificationService {
  MedicationNotificationService._();
  static final MedicationNotificationService instance = MedicationNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Set<int> _doseNotificationIds = {};
  final Set<int> _pillBoxNotificationIds = {};
  bool _ready = false;
  String? _lastCareGroupId;
  List<CareGroupMedication> _lastMeds = const [];
  int? _lastQuietStartMin;
  int? _lastQuietEndMin;
  void Function(String payload)? _dosePayloadHandler;
  void Function(String payload)? _pillBoxPayloadHandler;
  final List<String> _deferredDosePayloads = [];
  final List<String> _deferredPillBoxPayloads = [];
  void Function(String payload)? _chatPayloadHandler;
  final List<String> _deferredChatPayloads = [];

  static const String _channelId = "careshare_medications";
  static const String _channelName = "Medication reminders";
  static const String _chatChannelId = "careshare_chat";
  static const String _chatChannelName = "Group chat";

  void setPillBoxPayloadHandler(void Function(String payload)? handler) {
    _pillBoxPayloadHandler = handler;
    for (final p in _deferredPillBoxPayloads) {
      handler?.call(p);
    }
    _deferredPillBoxPayloads.clear();
  }

  void setDosePayloadHandler(void Function(String payload)? handler) {
    _dosePayloadHandler = handler;
    for (final p in _deferredDosePayloads) {
      handler?.call(p);
    }
    _deferredDosePayloads.clear();
  }

  void setChatPayloadHandler(void Function(String payload)? handler) {
    _chatPayloadHandler = handler;
    for (final p in _deferredChatPayloads) {
      handler?.call(p);
    }
    _deferredChatPayloads.clear();
  }

  void _handlePayload(String? p) {
    if (p == null) {
      return;
    }
    if (p.startsWith("missed|")) {
      if (_dosePayloadHandler != null) {
        _dosePayloadHandler!(p);
      } else {
        _deferredDosePayloads.add(p);
      }
      return;
    }
    if (p.startsWith("dose|")) {
      if (_dosePayloadHandler != null) {
        _dosePayloadHandler!(p);
      } else {
        _deferredDosePayloads.add(p);
      }
      return;
    }
    if (p.startsWith("pillbox|")) {
      if (_pillBoxPayloadHandler != null) {
        _pillBoxPayloadHandler!(p);
      } else {
        _deferredPillBoxPayloads.add(p);
      }
      return;
    }
    if (p.startsWith("chat|")) {
      if (_chatPayloadHandler != null) {
        _chatPayloadHandler!(p);
      } else {
        _deferredChatPayloads.add(p);
      }
    }
  }

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
    await _plugin.initialize(
      settings: init,
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chatChannelId,
          _chatChannelName,
          description: "New messages in care team channels (foreground banner).",
          importance: Importance.high,
        ),
      );
      await android?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _handlePayload(launch?.notificationResponse?.payload);
    }

    _ready = true;
  }

  Future<void> onAppResumed() async {
    if (kIsWeb || !_ready) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final careGroupId = _lastCareGroupId;
      if (careGroupId != null && _lastMeds.isNotEmpty) {
        await syncMedications(
          careGroupId,
          _lastMeds,
          quietHoursStartMinute: _lastQuietStartMin,
          quietHoursEndMinute: _lastQuietEndMin,
        );
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
    _lastCareGroupId = null;
    _lastMeds = const [];
  }

  /// Schedules local notifications and returns the planned nudges (empty when skipped).
  Future<List<DoseNudge>> syncMedications(
    String careGroupId,
    List<CareGroupMedication> meds, {
    int? quietHoursStartMinute,
    int? quietHoursEndMinute,
  }) async {
    if (kIsWeb || !_ready) {
      return const [];
    }

    _lastCareGroupId = careGroupId;
    _lastMeds = List<CareGroupMedication>.from(meds);
    _lastQuietStartMin = quietHoursStartMinute;
    _lastQuietEndMin = quietHoursEndMinute;

    try {
      for (final id in _doseNotificationIds) {
        await _plugin.cancel(id: id);
      }
      _doseNotificationIds.clear();
    } catch (e) {
      debugPrint("cancel dose notifications before sync: $e");
    }

    if (defaultTargetPlatform == TargetPlatform.linux) {
      return const [];
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: "Reminders to take prescribed medicine (grouped by time).",
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

    final isWin = defaultTargetPlatform == TargetPlatform.windows;
    final nudges = buildDoseNudges(
      careGroupId: careGroupId,
      meds: meds,
      isWindows: isWin,
      quietHoursStartMinute: quietHoursStartMinute,
      quietHoursEndMinute: quietHoursEndMinute,
    );

    for (final n in nudges) {
      try {
        await _plugin.zonedSchedule(
          id: n.notificationId,
          scheduledDate: n.scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: "Medication",
          body: n.body,
          payload: n.payload,
          matchDateTimeComponents: n.dateTimeMatch,
        );
        _doseNotificationIds.add(n.notificationId);
      } catch (e, st) {
        debugPrint("zonedSchedule dose: $e\n$st");
      }
    }
    return nudges;
  }

  /// Schedules local reminders for upcoming pill box refills (separate ID range from dose nudges).
  Future<void> syncPillBoxRefillReminders(List<PillBoxRefillReminderPlan> plans) async {
    if (kIsWeb || !_ready) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }
    try {
      for (final id in _pillBoxNotificationIds) {
        await _plugin.cancel(id: id);
      }
      _pillBoxNotificationIds.clear();
    } catch (e) {
      debugPrint("cancel pill box notifications: $e");
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: "Reminders to refill pill boxes.",
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

    final now = tz.TZDateTime.now(tz.local);
    for (final plan in plans) {
      if (plan.scheduledAt.isBefore(DateTime.now().subtract(const Duration(hours: 12)))) {
        continue;
      }
      final scheduled = tz.TZDateTime.from(plan.scheduledAt, tz.local);
      if (scheduled.isBefore(now)) {
        continue;
      }
      try {
        await _plugin.zonedSchedule(
          id: plan.notificationId,
          scheduledDate: scheduled,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: "Pill box refill",
          body: plan.body,
          payload: plan.payload,
        );
        _pillBoxNotificationIds.add(plan.notificationId);
      } catch (e, st) {
        debugPrint("zonedSchedule pillbox: $e\n$st");
      }
    }
  }

  /// Foreground FCM: system notification is not shown; we mirror it here.
  Future<void> showChatForegroundNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    if (kIsWeb || !_ready) {
      return;
    }
    final id = (DateTime.now().millisecondsSinceEpoch % 100000) + 900000;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _chatChannelId,
        _chatChannelName,
        channelDescription: "New messages in care team channels.",
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
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e, st) {
      debugPrint("showChatForegroundNotification: $e\n$st");
    }
  }

  /// Foreground / data-only FCM for medication reminders (mirrors like chat).
  Future<void> showMedicationForegroundNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    if (kIsWeb || !_ready) {
      return;
    }
    final id = (DateTime.now().millisecondsSinceEpoch % 100000) + 800000;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: "Medication reminders for your care group.",
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
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e, st) {
      debugPrint("showMedicationForegroundNotification: $e\n$st");
    }
  }
}
