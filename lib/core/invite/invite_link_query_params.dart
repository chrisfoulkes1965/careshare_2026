import "package:flutter/foundation.dart";

/// Merges [routerUri]'s query with the browser URL on web (`Uri.base`).
///
/// When the SPA starts at [/loading], [routerUri] can temporarily omit `?invite=`
/// while [Uri.base] still has it — copy `invite` and `email` so invite flows work.
Map<String, String> mergeInviteLinkQueryParams({
  required String path,
  required Uri routerUri,
}) {
  final merged = Map<String, String>.from(routerUri.queryParameters);
  final normPath = normalizeAuthPath(path);
  if (normPath != "/sign-in" &&
      normPath != "/register" &&
      normPath != "/invite-existing-user") {
    return merged;
  }
  if (!kIsWeb) {
    return merged;
  }
  final base = Uri.base;
  if (normalizeAuthPath(base.path) != normPath) {
    return merged;
  }
  for (final e in base.queryParameters.entries) {
    final k = e.key;
    if (k != "invite" && k != "email") {
      continue;
    }
    if (e.value.isEmpty) {
      continue;
    }
    final cur = merged[k];
    if (cur == null || cur.isEmpty) {
      merged[k] = e.value;
    }
  }
  return merged;
}

/// Canonical path for [/sign-in] vs [/sign-in/].
String normalizeAuthPath(String path) {
  if (path.length > 1 && path.endsWith("/")) {
    return path.substring(0, path.length - 1);
  }
  return path.isEmpty ? "/" : path;
}

/// Full URI with merged invite/email query (for redirects and mismatched-account checks).
Uri effectiveInviteAwareUri(Uri routerUri) {
  final qp = mergeInviteLinkQueryParams(
    path: routerUri.path,
    routerUri: routerUri,
  );
  return Uri(
    path: normalizeAuthPath(routerUri.path),
    queryParameters: qp.isEmpty ? null : qp,
    fragment: routerUri.fragment.isEmpty ? null : routerUri.fragment,
  );
}
