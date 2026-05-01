import "package:cloud_firestore/cloud_firestore.dart";

class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.parentFolderId,
    required this.inTrash,
    this.trashedAt,
    required this.createdBy,
    this.createdAt,
  });

  final String id;
  final String name;

  /// Empty string means root. Parent must not be in trash for active items.
  final String parentFolderId;
  final bool inTrash;
  final DateTime? trashedAt;
  final String createdBy;
  final DateTime? createdAt;

  static LibraryFolder fromDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    Timestamp? t(dynamic v) => v is Timestamp ? v : null;
    return LibraryFolder(
      id: id,
      name: (data["name"] as String?)?.trim() ?? "Folder",
      parentFolderId: (data["parentFolderId"] as String?)?.trim() ?? "",
      inTrash: data["inTrash"] as bool? ?? false,
      trashedAt: t(data["trashedAt"])?.toDate(),
      createdBy: (data["createdBy"] as String?)?.trim() ?? "",
      createdAt: t(data["createdAt"])?.toDate(),
    );
  }
}
