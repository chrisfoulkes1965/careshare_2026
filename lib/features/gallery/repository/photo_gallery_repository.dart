import "dart:async";
import "dart:typed_data";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../models/gallery_photo.dart";

class PhotoGalleryRepository {
  PhotoGalleryRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  static const int _maxBytes = 8 * 1024 * 1024;
  static const Duration _uploadTimeout = Duration(minutes: 2);

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _photos(String careGroupId) =>
      FirebaseFirestore.instance.collection("careGroups").doc(careGroupId).collection("galleryPhotos");

  String _safeFileName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
    if (n.isEmpty) n = "photo";
    return n.length > 120 ? n.substring(0, 120) : n;
  }

  String _extensionForMime(String? mime, String fallbackName) {
    final m = mime?.toLowerCase() ?? "";
    if (m.contains("png")) return "png";
    if (m.contains("webp")) return "webp";
    if (m.contains("gif")) return "gif";
    if (m.contains("jpeg") || m.contains("jpg")) return "jpg";
    final dot = fallbackName.lastIndexOf(".");
    if (dot > 0 && dot < fallbackName.length - 1) {
      return fallbackName.substring(dot + 1).toLowerCase();
    }
    return "jpg";
  }

  Stream<List<GalleryPhoto>> watchPhotos(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _photos(careGroupId)
        .orderBy("uploadedAt", descending: true)
        .limit(500)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => GalleryPhoto.fromDoc(d.id, d.data()))
              .where((p) => p.downloadUrl.isNotEmpty)
              .toList(),
        );
  }

  Future<void> uploadPhoto({
    required String careGroupId,
    required List<int> bytes,
    required String fileName,
    String? mimeType,
    String? caption,
  }) async {
    if (!_firebaseReady) {
      throw StateError("Firebase is not ready.");
    }
    if (bytes.isEmpty) {
      throw ArgumentError("Photo is empty.");
    }
    if (bytes.length > _maxBytes) {
      throw ArgumentError("Photo must be ${_maxBytes ~/ (1024 * 1024)} MB or smaller.");
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError("Not signed in.");
    }
    final docRef = _photos(careGroupId).doc();
    final photoId = docRef.id;
    final ext = _extensionForMime(mimeType, fileName);
    final safe = _safeFileName(fileName);
    final storageName = "${DateTime.now().millisecondsSinceEpoch}_$safe.$ext";
    final storageRef = FirebaseStorage.instance.ref().child(
          "careGroups/$careGroupId/gallery/$photoId/$storageName",
        );
    final meta = SettableMetadata(
      contentType: mimeType ?? "image/jpeg",
    );
    await storageRef
        .putData(
          Uint8List.fromList(bytes),
          meta,
        )
        .timeout(_uploadTimeout);
    final downloadUrl = await storageRef.getDownloadURL().timeout(_uploadTimeout);
    await docRef.set({
      "storagePath": storageRef.fullPath,
      "downloadUrl": downloadUrl,
      "uploadedBy": user.uid,
      "uploadedAt": FieldValue.serverTimestamp(),
      if (caption != null && caption.trim().isNotEmpty) "caption": caption.trim(),
    });
  }

  Future<void> deletePhoto({
    required String careGroupId,
    required GalleryPhoto photo,
  }) async {
    if (!_firebaseReady) {
      throw StateError("Firebase is not ready.");
    }
    try {
      if (photo.storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref(photo.storagePath).delete();
      }
    } catch (_) {
      // Storage object may already be gone; continue removing Firestore row.
    }
    await _photos(careGroupId).doc(photo.id).delete();
  }
}
