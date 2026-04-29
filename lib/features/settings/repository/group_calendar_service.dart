import "dart:async";

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

  /// True when **`functions/gcal/syncInboundGoogleCalendar.js`** **`resolveCalendarIdForCareGroupDoc`**
  /// could find calendar metadata (same precedence: this doc → linked doc → shell docs pointing here).
  /// Uses only Firestore **`careGroups`**, not **`config/groupCalendar`**.
  Future<bool> hasResolvedInboundCalendarForDataDoc(String dataDocId) async {
    if (!_ok || dataDocId.trim().isEmpty) {
      return false;
    }
    final root = await FirebaseFirestore.instance
        .collection("careGroups")
        .doc(dataDocId)
        .get();
    if (!root.exists) {
      return false;
    }
    final d = root.data() ?? {};
    if (_localInboundCalendarFromCareGroupDoc(d).hasAny) {
      return true;
    }
    final linked = (d["careGroupId"] as String?)?.trim();
    if (linked != null && linked.isNotEmpty) {
      final o = await FirebaseFirestore.instance
          .collection("careGroups")
          .doc(linked)
          .get();
      if (o.exists &&
          _localInboundCalendarFromCareGroupDoc(o.data() ?? {}).hasAny) {
        return true;
      }
    }
    final teams = await FirebaseFirestore.instance
        .collection("careGroups")
        .where("careGroupId", isEqualTo: dataDocId)
        .limit(5)
        .get();
    for (final doc in teams.docs) {
      if (_localInboundCalendarFromCareGroupDoc(doc.data()).hasAny) {
        return true;
      }
    }
    return false;
  }

  /// Recomputes [hasResolvedInboundCalendarForDataDoc] when the merged **`careGroups`** doc or
  /// any **`careGroups`** shell with **`careGroupId ==`** [dataDocId] changes.
  Stream<bool> watchResolvedInboundCalendarForDataDoc(String dataDocId) {
    final id = dataDocId.trim();
    if (!_ok || id.isEmpty) {
      return Stream<bool>.value(false);
    }
    final fb = FirebaseFirestore.instance;
    final docRef = fb.collection("careGroups").doc(id);
    final shells = fb
        .collection("careGroups")
        .where("careGroupId", isEqualTo: id)
        .limit(5);
    Future<void> emit(StreamController<bool> c) async {
      try {
        final v = await hasResolvedInboundCalendarForDataDoc(id);
        if (!c.isClosed) {
          c.add(v);
        }
      } catch (_) {
        if (!c.isClosed) {
          c.add(false);
        }
      }
    }

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subShellDoc;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subShells;

    late StreamController<bool> c;
    c = StreamController<bool>(
      onListen: () {
        subShellDoc = docRef.snapshots().listen((_) => unawaited(emit(c)));
        subShells = shells.snapshots().listen((_) => unawaited(emit(c)));
        unawaited(emit(c));
      },
      onCancel: () async {
        await subShellDoc?.cancel();
        await subShells?.cancel();
      },
    );
    return c.stream;
  }

  GroupCalendarResult _localInboundCalendarFromCareGroupDoc(
    Map<String, dynamic> d,
  ) {
    final map = _fromGroupCalendarMap(d["groupCalendar"]);
    if (map.hasAny) {
      return map;
    }
    final legacy = (d["groupCalendarId"] as String?)?.trim();
    if (legacy != null && legacy.isNotEmpty) {
      return GroupCalendarResult(
        calendarId: legacy,
        icalUrl: null,
      );
    }
    return const GroupCalendarResult();
  }

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
