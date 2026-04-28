import "package:flutter/foundation.dart";
import "package:url_launcher/url_launcher.dart";

/// WhatsApp “click to chat” uses international numbers with country code, digits only
/// (see https://faq.whatsapp.com/general/chats/how-to-use-click-to-chat).
String? whatsAppDigitsFromPhoneField(String? raw) {
  if (raw == null) {
    return null;
  }
  final t = raw.trim();
  if (t.isEmpty) {
    return null;
  }
  final buf = StringBuffer();
  var i = 0;
  if (t.startsWith("+")) {
    i = 1;
  }
  for (; i < t.length; i++) {
    final c = t.codeUnitAt(i);
    if (c >= 0x30 && c <= 0x39) {
      buf.writeCharCode(c);
    }
  }
  final d = buf.toString();
  if (d.length < 8) {
    return null;
  }
  return d;
}

/// Opens WhatsApp (app or web) to chat with [phone] after normalizing. Optional [prefill] draft message.
Future<WhatsAppLaunchResult> openWhatsAppToPhone({
  required String phone,
  String? prefill,
}) async {
  final digits = whatsAppDigitsFromPhoneField(phone);
  if (digits == null) {
    return WhatsAppLaunchResult.invalidPhone;
  }
  final b = prefill == null ? null : (prefill.trim().isEmpty ? null : prefill);
  final uri = b == null
      ? Uri.parse("https://wa.me/$digits")
      : Uri.parse(
          "https://wa.me/$digits?text=${Uri.encodeComponent(b)}",
        );
  if (!await canLaunchUrl(uri)) {
    return WhatsAppLaunchResult.couldNotLaunch;
  }
  final ok = await launchUrl(
    uri,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
  );
  return ok ? WhatsAppLaunchResult.opened : WhatsAppLaunchResult.couldNotLaunch;
}

/// Result of [openWhatsAppToPhone] so UI can show a specific hint.
enum WhatsAppLaunchResult {
  opened,
  couldNotLaunch,
  invalidPhone,
}

String whatsAppErrorHint(WhatsAppLaunchResult r) {
  return switch (r) {
    WhatsAppLaunchResult.opened => "",
    WhatsAppLaunchResult.couldNotLaunch =>
      "Could not open WhatsApp. Try again or install the app on this device.",
    WhatsAppLaunchResult.invalidPhone =>
      "Enter a phone number with country code (e.g. +44 7700 900123) for WhatsApp.",
  };
}
