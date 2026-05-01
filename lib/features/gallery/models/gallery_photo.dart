/// Firestore: `careGroups/{careGroupId}/galleryPhotos/{photoId}`.
class GalleryPhoto {
  const GalleryPhoto({
    required this.id,
    required this.downloadUrl,
    required this.storagePath,
    required this.uploadedBy,
    this.uploadedAt,
    this.caption,
  });

  final String id;
  final String downloadUrl;
  final String storagePath;
  final String uploadedBy;
  final DateTime? uploadedAt;
  final String? caption;

  static GalleryPhoto fromDoc(String id, Map<String, dynamic> data) {
    DateTime? uploadedAt;
    final rawAt = data["uploadedAt"];
    if (rawAt != null) {
      try {
        uploadedAt = (rawAt as dynamic).toDate() as DateTime?;
      } catch (_) {
        uploadedAt = null;
      }
    }
    return GalleryPhoto(
      id: id,
      downloadUrl: (data["downloadUrl"] as String?)?.trim() ?? "",
      storagePath: (data["storagePath"] as String?)?.trim() ?? "",
      uploadedBy: (data["uploadedBy"] as String?)?.trim() ?? "",
      uploadedAt: uploadedAt,
      caption: (data["caption"] as String?)?.trim(),
    );
  }
}
