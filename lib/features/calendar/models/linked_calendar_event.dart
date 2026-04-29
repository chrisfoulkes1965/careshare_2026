import "package:cloud_firestore/cloud_firestore.dart";
import "package:equatable/equatable.dart";

/// One person extracted from imported Google Calendar event metadata on
/// [careGroups/.../linkedCalendarEvents].
final class CalendarEventPerson extends Equatable {
  const CalendarEventPerson({
    required this.email,
    this.displayName,
    this.role,
  });

  final String email;
  final String? displayName;
  final String? role;

  static CalendarEventPerson? maybeFrom(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final m = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    final e = ((m["email"] as String?) ?? "").trim().toLowerCase();
    if (e.isEmpty || !e.contains("@")) {
      return null;
    }
    if (_isSyntheticCalendarIdentity(e)) {
      return null;
    }
    final name = (m["name"] as String?)?.trim();
    final role = (m["role"] as String?)?.trim();
    return CalendarEventPerson(
      email: e,
      displayName: (name != null && name.isNotEmpty) ? name : null,
      role: (role != null && role.isNotEmpty) ? role : null,
    );
  }

  @override
  List<Object?> get props => [email, displayName, role];
}

bool _isSyntheticCalendarIdentity(String emailLowercase) =>
    emailLowercase.endsWith("@resource.calendar.google.com") ||
    emailLowercase.endsWith("@group.calendar.google.com");

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
    this.calendarPeople = const [],
  });

  final String id;
  final String gcalEventId;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;

  /// When set, tapping opens this URL (usually Google Calendar event page).
  final String? htmlLink;

  /// Organizer and attendees synced from Google (excluding resource accounts).
  final List<CalendarEventPerson> calendarPeople;

  static LinkedCalendarEvent fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    final start = data["startAt"];
    final end = data["endAt"];
    final rawTitle = (data["title"] as String?)?.trim() ?? "";
    final link = (data["htmlLink"] as String?)?.trim();
    final cp = data["calendarPeople"];
    final people = <CalendarEventPerson>[];
    if (cp is List) {
      for (final e in cp) {
        final parsed = CalendarEventPerson.maybeFrom(e);
        if (parsed != null) {
          people.add(parsed);
        }
      }
    }
    return LinkedCalendarEvent(
      id: d.id,
      gcalEventId: (data["gcalEventId"] as String?) ?? "",
      title: rawTitle.isEmpty ? "Event" : rawTitle,
      startAt: start is Timestamp ? start.toDate() : DateTime.now(),
      endAt: end is Timestamp ? end.toDate() : null,
      allDay: data["allDay"] == true,
      htmlLink: link != null && link.isEmpty ? null : link,
      calendarPeople: people,
    );
  }
}
