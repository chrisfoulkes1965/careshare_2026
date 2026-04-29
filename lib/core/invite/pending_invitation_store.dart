import "package:flutter/foundation.dart" show kIsWeb;
import "package:shared_preferences/shared_preferences.dart";

/// Persists `invitations/{id}` from `/sign-in?invite=` so it survives Google sign-in
/// and is applied in [ProfileCubit] after authentication.
abstract final class PendingInvitationStore {
  static const _key = "pending_invitation_doc_id";

  static Future<void> saveFromQueryIfPresent(String? invitationId) async {
    final t = invitationId?.trim();
    if (t == null || t.isEmpty) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, t);
  }

  /// On Flutter web, persist `?invite=` before the first [ProfileCubit] load so
  /// invitees always see [InviteProfileScreen] instead of silent redemption.
  static Future<void> primeFromStartupUrlIfWeb() async {
    if (!kIsWeb) {
      return;
    }
    await saveFromQueryIfPresent(Uri.base.queryParameters["invite"]);
  }

  static Future<String?> read() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key)?.trim();
    return s != null && s.isNotEmpty ? s : null;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
