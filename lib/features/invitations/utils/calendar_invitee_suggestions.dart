import "../../calendar/models/linked_calendar_event.dart";
import "../models/care_invitation.dart";

/// Deduplicated person from synced calendar metadata for invite suggestions UI.
final class CalendarInviteeSuggestion implements Comparable<CalendarInviteeSuggestion> {
  const CalendarInviteeSuggestion({
    required this.emailNormalized,
    required this.titleLine,
    this.sampleEventTitle,
  });

  final String emailNormalized;
  final String titleLine;
  final String? sampleEventTitle;

  @override
  int compareTo(CalendarInviteeSuggestion other) =>
      emailNormalized.compareTo(other.emailNormalized);
}

class _PersonAccum {
  _PersonAccum({required this.titleLine, this.sampleEventTitle});

  String titleLine;
  String? sampleEventTitle;
}

/// Merges people from [events], then excludes the signed-in email and anyone listed on a
/// pending or accepted invitation (already in your invite workflow as member or queued).
///
/// [CareGroupMember] does not expose emails client-side for other members — using invitation
/// records covers typical join-by-email flows; remaining calendar identities may appear even
/// if they are actually members who joined without invitation.
List<CalendarInviteeSuggestion> mergedCalendarInviteeSuggestions({
  required List<LinkedCalendarEvent> events,
  required Iterable<CareInvitation> invitations,
  required String? currentUserEmailNormalized,
  int maxEventsToScan = 400,
}) {
  final excluded = <String>{
    if (currentUserEmailNormalized != null &&
        currentUserEmailNormalized.trim().isNotEmpty)
      currentUserEmailNormalized.trim().toLowerCase(),
    for (final inv in invitations)
      if (inv.status == "pending" || inv.status == "accepted")
        inv.invitedEmail.trim().toLowerCase(),
  };

  final merged = <String, _PersonAccum>{};

  var scanned = 0;
  for (final ev in events) {
    if (scanned >= maxEventsToScan) {
      break;
    }
    scanned++;

    final evTitle =
        ev.title.trim().isNotEmpty ? ev.title.trim() : null;

    for (final p in ev.calendarPeople) {
      final key = p.email.trim().toLowerCase();
      if (key.isEmpty || excluded.contains(key)) {
        continue;
      }
      final display = (p.displayName != null && p.displayName!.trim().isNotEmpty)
          ? p.displayName!.trim()
          : key;
      final prior = merged[key];
      if (prior == null) {
        merged[key] =
            _PersonAccum(titleLine: display, sampleEventTitle: evTitle);
      } else {
        prior.sampleEventTitle ??= evTitle;
      }
    }
  }

  final out = <CalendarInviteeSuggestion>[
    for (final e in merged.entries)
      CalendarInviteeSuggestion(
        emailNormalized: e.key,
        titleLine: e.value.titleLine,
        sampleEventTitle: e.value.sampleEventTitle,
      ),
  ];
  out.sort();
  return out;
}
