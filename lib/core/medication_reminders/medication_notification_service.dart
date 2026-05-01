import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:flutter_timezone/flutter_timezone.dart";
import "package:timezone/data/latest_all.dart" as tz_data;
import "package:timezone/timezone.dart" as tz;

import "medication_dose_group_planner.dart";
import "../../features/medications/models/care_group_medication.dart";

/// Grouped local reminders; tap opens a confirmation flow (set [setDosePayloadHandler] from [app.dart]).
/// Foreground FCM for chat also uses the same plugin (set [setChatPayloadHandler]).
final class MedicationNotificationService {
  MedicationNotificationService._();
  static final MedicationNotificationService instance = MedicationNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _lastCareGroupId;
  List<CareGroupMedication> _lastMeds = const [];
  int? _lastQuietStartMin;
  int? _lastQuietEndMin;
  void Function(String payload)? _dosePayloadHandler;
  final List<String> _deferredDosePayloads = [];
  void Function(String payload)? _chatPayloadHandler;
  final List<String> _deferredChatPayloads = [];

  static const String _channelId = "careshare_medications";
  static const String _channelName = "Medication reminders";
  static const String _chatChannelId = "careshare_chat";
  static const String _chatChannelName = "Group chat";

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
    if (p.startsWith("dose|")) {
      if (_dosePayloadHandler != null) {
        _dosePayloadHandler!(p);
      } else {
        _deferredDosePayloads.add(p);
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

  Future<void> syncMedications(
    String careGroupId,
    List<CareGroupMedication> meds, {
    int? quietHoursStartMinute,
    int? quietHoursEndMinute,
  }) async {
    if (kIsWeb || !_ready) {
      return;
    }

    _lastCareGroupId = careGroupId;
    _lastMeds = List<CareGroupMedication>.from(meds);
    _lastQuietStartMin = quietHoursStartMinute;
    _lastQuietEndMin = quietHoursEndMinute;

    try {
      await _plugin.cancelAll().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint("cancelAll: timed out, continuing sync");
        },
      );
    } catch (e) {
      debugPrint("cancel before sync: $e");
    }

    if (defaultTargetPlatform == TargetPlatform.linux) {
      return;
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
      } catch (e, st) {
        debugPrint("zonedSchedule dose: $e\n$st");
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
