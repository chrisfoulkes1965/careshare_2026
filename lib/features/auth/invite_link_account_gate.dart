import "../../../core/invite/invite_link_query_params.dart";
import "bloc/auth_state.dart";

/// Redirect target when auth is still [AuthStatus.unknown] but the router matched
/// [/loading] (or something else) while the browser URI is `/sign-in?invite=…`
/// — sync navigation so invite params survive.
String? inviteAuthScreenSyncRedirectTarget({
  required String matchedLocation,
  required Uri uri,
}) {
  final effective = effectiveInviteAwareUri(uri);
  final invite = effective.queryParameters["invite"]?.trim();
  if (invite == null || invite.isEmpty) {
    return null;
  }
  final path = normalizeAuthPath(effective.path);
  if (path != "/sign-in" && path != "/register") {
    return null;
  }
  if (matchedLocation == path) {
    return null;
  }
  return "$path${effective.hasQuery ? "?${effective.query}" : ""}";
}

/// [/sign-in] or [/register] with an `invite` query (invite landing link).
bool inviteUriPointsAtAuthScreenWithInvite(Uri uri) {
  final effective = effectiveInviteAwareUri(uri);
  final invite = effective.queryParameters["invite"]?.trim();
  if (invite == null || invite.isEmpty) {
    return false;
  }
  final path = normalizeAuthPath(effective.path);
  return path == "/sign-in" || path == "/register";
}

/// True when [uri] contains both `invite` and `email` and the Firebase user is
/// signed in as a **different** account than `email`.
///
/// Typical case: the inviter clicks the invite URL while still logged in as
/// themselves; they must switch sessions so the invitation can redeem for the
/// intended recipient (`email`).
bool inviteSignedLinkNeedsDifferentFirebaseUser({
  required AuthState authState,
  required Uri uri,
}) {
  if (authState.status != AuthStatus.authenticated || authState.user == null) {
    return false;
  }
  final effective = effectiveInviteAwareUri(uri);
  final inviteId = effective.queryParameters["invite"]?.trim();
  final invitedEmail =
      effective.queryParameters["email"]?.trim().toLowerCase() ?? "";
  if (inviteId == null ||
      inviteId.isEmpty ||
      invitedEmail.isEmpty) {
    return false;
  }
  final current = authState.user!.email?.trim().toLowerCase();
  if (current == null || current.isEmpty) {
    return true;
  }
  return current != invitedEmail;
}
