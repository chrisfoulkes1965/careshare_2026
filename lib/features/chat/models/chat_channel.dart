import "package:cloud_firestore/cloud_firestore.dart";

/// `careGroups/{careGroupId}/chatChannels/{channelId}`
final class ChatChannel {
  const ChatChannel({
    required this.id,
    required this.name,
    this.description = "",
    this.topic = "general",
    this.whatsappInviteUrl,
    required this.memberUids,
    required this.createdBy,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String topic;

  /// Optional `https://chat.whatsapp.com/...` group invite; parallel discussion in WhatsApp (not auto-synced).
  final String? whatsappInviteUrl;
  final List<String> memberUids;
  final String createdBy;
  final DateTime? createdAt;

  static ChatChannel fromDoc(
    String id,
    Map<String, dynamic> d,
  ) {
    final members = d["memberUids"];
    final wa = d["whatsappInviteUrl"];
    return ChatChannel(
      id: id,
      name: (d["name"] as String?)?.trim() ?? "Channel",
      description: (d["description"] as String?)?.trim() ?? "",
      topic: (d["topic"] as String?)?.trim() ?? "general",
      whatsappInviteUrl:
          wa is String && wa.trim().isNotEmpty ? wa.trim() : null,
      memberUids: members is List
          ? members.map((e) => e.toString()).toList()
          : const <String>[],
      createdBy: (d["createdBy"] as String?) ?? "",
      createdAt: d["createdAt"] is Timestamp
          ? (d["createdAt"] as Timestamp).toDate()
          : null,
    );
  }
}
