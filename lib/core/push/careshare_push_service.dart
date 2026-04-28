import "dart:async";
import "dart:math" show Random;

import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:go_router/go_router.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../medication_reminders/medication_notification_service.dart";
import "../../features/user/repository/user_repository.dart";

const _kInstallKey = "careshare_device_installation_id";

/// FCM: registers device token on [users/uid/devicePushTokens], opens chat from taps.
final class CaresharePushService {
  CaresharePushService._();
  static final CaresharePushService instance = CaresharePushService._();

  UserRepository? _userRepository;
  GoRouter? _router;
  StreamSubscription<RemoteMessage?>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<User?>? _authSub;
  bool _started = false;
  String? _installId;
  String? _lastAuthUid;

  static String _platformLabel() {
    if (kIsWeb) {
      return "web";
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return "android";
      case TargetPlatform.iOS:
        return "ios";
      case TargetPlatform.macOS:
        return "macos";
      default:
        return "other";
    }
  }

  static String _buildChatPayload(String careGroupId, String channelId) {
    return "chat|$careGroupId|$channelId";
  }

  void _openChatFromData(Map<String, dynamic> data) {
    if (data["type"] != "chat") {
      return;
    }
    final cg = (data["careGroupId"] ?? "").toString();
    final ch = (data["channelId"] ?? "").toString();
    if (cg.isEmpty || ch.isEmpty) {
      return;
    }
    _openChat(cg, ch);
  }

  void _openChatFromPayload(String payload) {
    final p = payload.split("|");
    if (p.length < 3) {
      return;
    }
    if (p[0] != "chat") {
      return;
    }
    if (p[1].isEmpty || p[2].isEmpty) {
      return;
    }
    _openChat(p[1], p[2]);
  }

  void _openChat(String careGroupId, String channelId) {
    final r = _router;
    if (r == null) {
      return;
    }
    final q = Uri.encodeQueryComponent(careGroupId);
    r.push("/chat/$channelId?careGroupId=$q");
  }

  void bind({
    required GoRouter router,
    required UserRepository userRepository,
  }) {
    _router = router;
    _userRepository = userRepository;
    MedicationNotificationService.instance.setChatPayloadHandler(_openChatFromPayload);
    if (!_started) {
      return;
    }
    unawaited(_readInitialMessage());
  }

  Future<void> _readInitialMessage() async {
    if (kIsWeb) {
      return;
    }
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      if (m == null) {
        return;
      }
      if (kDebugMode) {
        debugPrint("FCM getInitialMessage: ${m.data}");
      }
      _openChatFromData(m.data);
    } catch (e) {
      debugPrint("getInitialMessage: $e");
    }
  }

  /// Call once after [Firebase.initializeApp] and [MedicationNotificationService.init] when messaging is used.
  Future<void> start() async {
    if (_started) {
      return;
    }
    if (kIsWeb) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }
    try {
      if (!kIsWeb) {
        final supported = await FirebaseMessaging.instance.isSupported();
        if (!supported) {
          return;
        }
      }
    } catch (e) {
      debugPrint("FCM isSupported: $e");
      return;
    }
    _started = true;
    if (kDebugMode) {
      debugPrint("FCM: messaging started");
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } else {
      await FirebaseMessaging.instance.requestPermission();
    }

    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
      if (kDebugMode) {
        debugPrint("FCM onMessageOpenedApp: ${m.data}");
      }
      _openChatFromData(m.data);
    });

    _foregroundSub = FirebaseMessaging.onMessage.listen((m) {
      if (kDebugMode) {
        debugPrint("FCM onMessage: ${m.data}");
      }
      if (m.data["type"] != "chat") {
        return;
      }
      final cg = (m.data["careGroupId"] ?? "").toString();
      final ch = (m.data["channelId"] ?? "").toString();
      if (cg.isEmpty || ch.isEmpty) {
        return;
      }
      final t = m.notification?.title?.trim() ?? "Group chat";
      final b = m.notification?.body?.trim() ?? "New message";
      unawaited(
        MedicationNotificationService.instance.showChatForegroundNotification(
          title: t,
          body: b,
          payload: _buildChatPayload(cg, ch),
        ),
      );
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      (user) async {
        if (user == null) {
          final prev = _lastAuthUid;
          _lastAuthUid = null;
          await onUserSignedOut(prev);
          return;
        }
        _lastAuthUid = user.uid;
        await _syncTokenForUser(user);
      },
    );
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance.getAPNSToken();
    }
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      await _syncTokenForUser(u);
    }
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      final u2 = FirebaseAuth.instance.currentUser;
      if (u2 != null) {
        unawaited(_writeTokenForUser(u2, token));
      }
    });
    if (_router != null) {
      await _readInitialMessage();
    }
  }

  Future<String> _installationId() async {
    if (_installId != null) {
      return _installId!;
    }
    final p = await SharedPreferences.getInstance();
    var v = p.getString(_kInstallKey);
    if (v == null || v.isEmpty) {
      const chars = "0123456789abcdef";
      final r = Random.secure();
      v = List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
      await p.setString(_kInstallKey, v);
    }
    _installId = v;
    return v;
  }

  Future<void> _syncTokenForUser(User user) async {
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t == null || t.isEmpty) {
        return;
      }
      await _writeTokenForUser(user, t);
    } catch (e) {
      debugPrint("getToken: $e");
    }
  }

  Future<void> _writeTokenForUser(User user, String token) async {
    final repo = _userRepository;
    if (repo == null || !repo.isAvailable) {
      return;
    }
    final id = await _installationId();
    await repo.upsertDevicePushToken(
      uid: user.uid,
      installationId: id,
      token: token,
      platform: _platformLabel(),
    );
  }

  /// Call when the user signs out to stop pushes to this device.
  Future<void> onUserSignedOut(String? previousUid) async {
    if (previousUid == null) {
      return;
    }
    final repo = _userRepository;
    if (repo == null || !repo.isAvailable) {
      return;
    }
    final id = await _installationId();
    try {
      await repo.removeDevicePushToken(uid: previousUid, installationId: id);
    } catch (e) {
      debugPrint("removeDevicePushToken: $e");
    }
  }

  Future<void> dispose() async {
    await _openedSub?.cancel();
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
    await _authSub?.cancel();
    _openedSub = null;
    _foregroundSub = null;
    _tokenSub = null;
    _authSub = null;
  }
}
