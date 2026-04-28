import "package:cloud_firestore/cloud_firestore.dart";

/// Mirrors `careGroups/{cgId}/linkedCalendarEvents` — Google Calendar events
/// imported by scheduled Cloud Functions (not created from the Flutter app).
final class LinkedCalendarEvent {
  const LinkedCalendarEvent({
    required this.id,
    required this.gcalEventId,
    required this.title,
    required this.startAt,
    this.endAt,
    this.allDay = false,
    this.htmlLink,
  });

  final String id;
  final String gcalEventId;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;

  /// When set, tapping opens this URL (usually Google Calendar event page).
  final String? htmlLink;

  static LinkedCalendarEvent fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    final start = data["startAt"];
    final end = data["endAt"];
    final rawTitle = (data["title"] as String?)?.trim() ?? "";
    final link = (data["htmlLink"] as String?)?.trim();
    return LinkedCalendarEvent(
      id: d.id,
      gcalEventId: (data["gcalEventId"] as String?) ?? "",
      title: rawTitle.isEmpty ? "Event" : rawTitle,
      startAt: start is Timestamp ? start.toDate() : DateTime.now(),
      endAt: end is Timestamp ? end.toDate() : null,
      allDay: data["allDay"] == true,
      htmlLink: link != null && link.isEmpty ? null : link,
    );
  }
}
