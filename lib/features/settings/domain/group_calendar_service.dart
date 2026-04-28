import "package:cloud_firestore/cloud_firestore.dart";
import "package:url_launcher/url_launcher.dart";

/// Per-care-group subscription + sync IDs live on **`careGroups/{docId}`** as map
/// **`groupCalendar`**: `icalUrl`, `calendarId`, optional `timezone` (IANA).
/// Legacy global doc `config/groupCalendar` is still read if the map is absent/empty.
class GroupCalendarResult {
  const GroupCalendarResult({this.icalUrl, this.calendarId});

  final String? icalUrl;
  final String? calendarId;

  bool get hasAny =>
      (icalUrl != null && icalUrl!.trim().isNotEmpty) ||
      (calendarId != null && calendarId!.trim().isNotEmpty);

  Uri? get googleCalendarOpenUri {
    final raw = calendarId?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Uri.parse(
      "https://calendar.google.com/calendar/r?cid=${Uri.encodeComponent(raw)}",
    );
  }
}

class GroupCalendarService {
  GroupCalendarService({required bool firebaseReady}) : _ok = firebaseReady;

  final bool _ok;

  /// Loads from **`careGroups/{careGroupDocId}.groupCalendar`**, then legacy **`config/groupCalendar`**.
  /// Use the same id as for **`/tasks`** (typically [UserProfile.activeCareGroupId] on [ProfileReady]).
  Future<GroupCalendarResult> fetchConfigForCareGroup(
      String? careGroupDocId) async {
    if (!_ok || careGroupDocId == null || careGroupDocId.isEmpty) {
      return const GroupCalendarResult();
    }
    final local = await FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupDocId)
        .get();
    if (local.exists) {
      final d = local.data() ?? {};
      final fromMap = _fromGroupCalendarMap(d["groupCalendar"]);
      if (fromMap.hasAny) {
        return fromMap;
      }
    }

    final global =
        await FirebaseFirestore.instance.doc("config/groupCalendar").get();
    if (!global.exists) {
      return const GroupCalendarResult();
    }
    final g = global.data() ?? {};
    final ical = (g["icalUrl"] as String?)?.trim();
    final cid = (g["calendarId"] as String?)?.trim();
    return GroupCalendarResult(icalUrl: ical, calendarId: cid);
  }

  static GroupCalendarResult _fromGroupCalendarMap(Object? raw) {
    if (raw is! Map) {
      return const GroupCalendarResult();
    }
    final ical = (raw["icalUrl"] as String?)?.trim();
    final cid = (raw["calendarId"] as String?)?.trim();
    return GroupCalendarResult(icalUrl: ical, calendarId: cid);
  }

  Future<void> launchGoogleCalendar(GroupCalendarResult r) async {
    final u = r.googleCalendarOpenUri;
    if (u == null) {
      return;
    }
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }
}
