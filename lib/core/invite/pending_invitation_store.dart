import "dart:convert";

import "package:flutter/foundation.dart" show kIsWeb;
import "package:shared_preferences/shared_preferences.dart";

/// Persists `invitations/{id}` from `/sign-in?invite=` so it survives Google sign-in
/// and is applied in [ProfileCubit] after authentication.
abstract final class PendingInvitationStore {
  static const _key = "pending_invitation_doc_id";
  static const _redeemedKey = "redeemed_invitation_doc_ids_json";

  /// Invite ids already redeemed — do not persist again from a stale `?invite=` URL while
  /// auth routes are still keyed off the link (prevents looping [InviteProfileScreen]).
  ///
  /// Mirrors [_redeemedDocIdsPersisted]; session-only optimisation.
  static final Set<String> _suppressQueryPersistenceForInviteIds = {};

  static Set<String>? _redeemedCache;

  static Future<Set<String>> _allRedeemedIds() async {
    if (_redeemedCache != null) {
      return {..._redeemedCache!, ..._suppressQueryPersistenceForInviteIds};
    }
    final disk = await _loadRedeemedFromPrefs();
    _redeemedCache = disk;
    return {...disk, ..._suppressQueryPersistenceForInviteIds};
  }

  static Future<Set<String>> _loadRedeemedFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_redeemedKey);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _appendRedeemedToPrefs(String invitationDocId) async {
    final t = invitationDocId.trim();
    if (t.isEmpty) return;
    final prior = await _loadRedeemedFromPrefs();
    final merged = {...prior, t};
    const max = 200;
    final list = merged.toList();
    final trimmed =
        list.length <= max ? list : list.sublist(list.length - max);
    final asSet = trimmed.toSet();
    _redeemedCache = asSet;
    final p = await SharedPreferences.getInstance();
    await p.setString(_redeemedKey, jsonEncode(asSet.toList()));
  }

  static Future<void> saveFromQueryIfPresent(String? invitationId) async {
    final t = invitationId?.trim();
    if (t == null || t.isEmpty) {
      return;
    }
    final redeemed = await _allRedeemedIds();
    if (redeemed.contains(t)) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, t);
  }

  /// Persist from `?invite=` only before the user is signed in. A session that already
  /// has Firebase auth but still shows `/sign-in?invite=…` in the address bar must not
  /// write the id back after [clearAfterInvitationRedeem].
  static Future<void> saveFromQueryForPreAuthUsersOnly({
    required bool isAuthenticated,
    String? invitationId,
  }) async {
    if (isAuthenticated) {
      return;
    }
    await saveFromQueryIfPresent(invitationId);
  }

  /// On Flutter web, persist `?invite=` before the first [ProfileCubit] load so
  /// invitees always see [InviteProfileScreen] instead of silent redemption.
  ///
  /// Skips ids already redeemed (persisted): every page load re-reads `/sign-in?invite=` from
  /// `Uri.base` and would otherwise refill [SharedPreferences] after [clear].
  static Future<void> primeFromStartupUrlIfWeb() async {
    if (!kIsWeb) {
      return;
    }
    await saveFromQueryIfPresent(Uri.base.queryParameters["invite"]);
  }

  static Future<String?> read() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key)?.trim();
    if (s == null || s.isEmpty) {
      return null;
    }
    final redeemed = await _allRedeemedIds();
    if (redeemed.contains(s)) {
      await p.remove(_key);
      return null;
    }
    return s;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  /// Clears storage and rejects future URL-based persistence for this id (session + prefs).
  static Future<void> clearAfterInvitationRedeem(String redeemedInvitationDocId) async {
    await clear();
    final t = redeemedInvitationDocId.trim();
    if (t.isNotEmpty) {
      _suppressQueryPersistenceForInviteIds.add(t);
      await _appendRedeemedToPrefs(t);
    }
  }

  /// True if this id was already accepted (persisted list). Used so [_load] cannot
  /// re-enable the invite gate from a stale [SharedPreferences] write.
  static Future<bool> isRecordedAsRedeemed(String invitationDocId) async {
    final t = invitationDocId.trim();
    if (t.isEmpty) {
      return false;
    }
    return (await _allRedeemedIds()).contains(t);
  }
}
