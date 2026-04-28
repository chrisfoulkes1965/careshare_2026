import "package:cloud_firestore/cloud_firestore.dart";

/// `.../chatChannels/{id}/messages/{messageId}` — in-app text only in this slice.
final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.createdBy,
    this.createdAt,
  });

  final String id;
  final String text;
  final String createdBy;
  final DateTime? createdAt;

  static ChatMessage fromDoc(
    String id,
    Map<String, dynamic> d,
  ) {
    return ChatMessage(
      id: id,
      text: (d["text"] as String?)?.trim() ?? "",
      createdBy: (d["createdBy"] as String?) ?? "",
      createdAt: d["createdAt"] is Timestamp
          ? (d["createdAt"] as Timestamp).toDate()
          : null,
    );
  }
}
