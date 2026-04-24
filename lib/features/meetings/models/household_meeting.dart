import "package:cloud_firestore/cloud_firestore.dart";

/// `careGroups/{hid}/meetings/{id}` — care coordination meetings (agenda, notes).
final class CareGroupMeeting {
  const CareGroupMeeting({
    required this.id,
    required this.title,
    required this.createdBy,
    this.body,
    this.location,
    this.meetingAt,
    this.createdAt,
  });

  final String id;
  final String title;
  final String createdBy;
  final String? body;
  final String? location;
  final DateTime? meetingAt;
  final DateTime? createdAt;

  static CareGroupMeeting fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final meetingAt = data["meetingAt"];
    final created = data["createdAt"];
    return CareGroupMeeting(
      id: d.id,
      title: (data["title"] as String?)?.trim() ?? "Meeting",
      createdBy: (data["createdBy"] as String?) ?? "",
      body: (data["body"] as String?)?.trim(),
      location: (data["location"] as String?)?.trim(),
      meetingAt: meetingAt is Timestamp ? meetingAt.toDate() : null,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}
