import "package:equatable/equatable.dart";

/// Per-channel delivery for a class of alerts (stored under `users/{uid}.alertPreferences`).
final class AlertChannels extends Equatable {
  const AlertChannels({
    this.inApp = true,
    this.email = false,
    this.pushApp = true,
    this.sms = false,
  });

  /// Banners, dialogs, and other UI while using the app.
  final bool inApp;

  /// Email (requires backend delivery; preference is stored for when wired).
  final bool email;

  /// Push notification on this device (mobile/desktop app when FCM is available).
  final bool pushApp;

  /// SMS — not wired yet; kept for future use.
  final bool sms;

  static AlertChannels fromFirestore(Object? raw) {
    if (raw is! Map) {
      return const AlertChannels();
    }
    return AlertChannels(
      inApp: raw["inApp"] != false,
      email: raw["email"] == true,
      pushApp: raw["pushApp"] != false,
      sms: raw["sms"] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "inApp": inApp,
      "email": email,
      "pushApp": pushApp,
      "sms": sms,
    };
  }

  AlertChannels copyWith({
    bool? inApp,
    bool? email,
    bool? pushApp,
    bool? sms,
  }) {
    return AlertChannels(
      inApp: inApp ?? this.inApp,
      email: email ?? this.email,
      pushApp: pushApp ?? this.pushApp,
      sms: sms ?? this.sms,
    );
  }

  @override
  List<Object?> get props => [inApp, email, pushApp, sms];
}

/// User-level choices for which notifications go out on which channel.
final class UserAlertPreferences extends Equatable {
  const UserAlertPreferences({
    this.medicationReorder = const AlertChannels(),
    this.medicationDue = const AlertChannels(),
  });

  /// When on-hand supply is within the care group’s “reorder lead” window.
  final AlertChannels medicationReorder;

  /// Due-dose reminders (local schedule + optional server push mirror).
  final AlertChannels medicationDue;

  static UserAlertPreferences fromFirestore(Object? raw) {
    if (raw is! Map) {
      return const UserAlertPreferences();
    }
    return UserAlertPreferences(
      medicationReorder: AlertChannels.fromFirestore(raw["medicationReorder"]),
      medicationDue: AlertChannels.fromFirestore(raw["medicationDue"]),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "medicationReorder": medicationReorder.toMap(),
      "medicationDue": medicationDue.toMap(),
    };
  }

  UserAlertPreferences copyWith({
    AlertChannels? medicationReorder,
    AlertChannels? medicationDue,
  }) {
    return UserAlertPreferences(
      medicationReorder: medicationReorder ?? this.medicationReorder,
      medicationDue: medicationDue ?? this.medicationDue,
    );
  }

  @override
  List<Object?> get props => [medicationReorder, medicationDue];
}
