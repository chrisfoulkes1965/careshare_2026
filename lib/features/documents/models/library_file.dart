import "package:cloud_firestore/cloud_firestore.dart";

class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.displayName,
    required this.storagePath,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.folderId,
    required this.inTrash,
    this.trashedAt,
    required this.uploadedBy,
    this.uploadedAt,
    this.contentType,
  });

  final String id;
  final String displayName;
  final String storagePath;
  final String downloadUrl;
  final int sizeBytes;

  /// Empty string = file at library root in [folderId].
  final String folderId;
  final bool inTrash;
  final DateTime? trashedAt;
  final String uploadedBy;
  final DateTime? uploadedAt;
  final String? contentType;

  static LibraryFile fromDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    Timestamp? ts(dynamic v) => v is Timestamp ? v : null;
    return LibraryFile(
      id: id,
      displayName: (data["displayName"] as String?)?.trim() ?? "File",
      storagePath: (data["storagePath"] as String?)?.trim() ?? "",
      downloadUrl: (data["downloadUrl"] as String?)?.trim() ?? "",
      sizeBytes: (data["sizeBytes"] as num?)?.round() ?? 0,
      folderId: (data["folderId"] as String?)?.trim() ?? "",
      inTrash: data["inTrash"] as bool? ?? false,
      trashedAt: ts(data["trashedAt"])?.toDate(),
      uploadedBy: (data["uploadedBy"] as String?)?.trim() ?? "",
      uploadedAt: ts(data["uploadedAt"])?.toDate(),
      contentType: (data["contentType"] as String?)?.trim(),
    );
  }
}
