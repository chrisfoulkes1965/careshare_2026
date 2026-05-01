import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:file_picker/file_picker.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../../tasks/repository/platform_file_read_io.dart" if (dart.library.html) "../../tasks/repository/platform_file_read_web.dart" as platform_file_read;
import "../models/library_file.dart";
import "../models/library_folder.dart";

class DocumentsLibraryRepository {
  DocumentsLibraryRepository({required bool firebaseReady})
      : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  static const int _maxBytes = 10 * 1024 * 1024;
  static const Duration _uploadTimeout = Duration(minutes: 2);
  static const Duration _opTimeout = Duration(minutes: 1);

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _folders(String careGroupId) =>
      FirebaseFirestore.instance
          .collection("careGroups")
          .doc(careGroupId)
          .collection("docLibraryFolders");

  CollectionReference<Map<String, dynamic>> _files(String careGroupId) =>
      FirebaseFirestore.instance
          .collection("careGroups")
          .doc(careGroupId)
          .collection("docLibraryFiles");

  String _safeFileName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
    if (n.isEmpty) n = "file";
    return n.length > 200 ? n.substring(0, 200) : n;
  }

  Future<T> _withTimeout<T>(Future<T> f) {
    return f.timeout(
      _opTimeout,
      onTimeout: () {
        throw TimeoutException(
          "The operation is taking too long. Check your network and try again.",
        );
      },
    );
  }

  /// Folders in [parentFolderId] (empty = root) matching [inTrash] state.
  Stream<List<LibraryFolder>> watchFoldersInParent(
    String careGroupId, {
    required String parentFolderId,
    required bool inTrash,
  }) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _folders(careGroupId)
        .where("parentFolderId", isEqualTo: parentFolderId)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => LibraryFolder.fromDoc(
                  d.id,
                  d.data(),
                ),
              )
              .where((f) => f.inTrash == inTrash)
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(
                    b.name.toLowerCase(),
                  ),
            ),
        );
  }

  /// All trashed folders (any parent).
  Stream<List<LibraryFolder>> watchTrashedFolders(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _folders(careGroupId)
        .where("inTrash", isEqualTo: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => LibraryFolder.fromDoc(
                  d.id,
                  d.data(),
                ),
              )
              .toList()
            ..sort(
              (a, b) {
                final ta = a.trashedAt ?? a.createdAt ?? DateTime(1970);
                final tb = b.trashedAt ?? b.createdAt ?? DateTime(1970);
                return tb.compareTo(ta);
              },
            ),
        );
  }

  /// Files in [folderId] (empty = root) for [inTrash] state.
  Stream<List<LibraryFile>> watchFilesInFolder(
    String careGroupId, {
    required String folderId,
    required bool inTrash,
  }) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _files(careGroupId)
        .where("folderId", isEqualTo: folderId)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => LibraryFile.fromDoc(
                  d.id,
                  d.data(),
                ),
              )
              .where((f) => f.inTrash == inTrash)
              .toList()
            ..sort(
              (a, b) => a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  ),
            ),
        );
  }

  /// All non-trashed folders (for move-to picker). Unsorted.
  Stream<List<LibraryFolder>> watchAllActiveFolders(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _folders(careGroupId)
        .where("inTrash", isEqualTo: false)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => LibraryFolder.fromDoc(
                  d.id,
                  d.data(),
                ),
              )
              .toList(),
        );
  }

  Stream<List<LibraryFile>> watchTrashedFiles(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _files(careGroupId)
        .where("inTrash", isEqualTo: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => LibraryFile.fromDoc(
                  d.id,
                  d.data(),
                ),
              )
              .toList()
            ..sort(
              (a, b) {
                final ta = a.trashedAt ?? a.uploadedAt ?? DateTime(1970);
                final tb = b.trashedAt ?? b.uploadedAt ?? DateTime(1970);
                return tb.compareTo(ta);
              },
            ),
        );
  }

  /// Public: subtree folder ids (including [rootId]) for move / exclude from targets.
  Future<Set<String>> folderSubtreeIds(
    String careGroupId, {
    required String rootId,
  }) =>
      _folderTreeIds(careGroupId, rootId: rootId);

  /// Folder id set = [rootId] plus all descendants in the folder tree.
  Future<Set<String>> _folderTreeIds(
    String careGroupId, {
    required String rootId,
  }) async {
    final all = <String>{rootId};
    final q = <String>[rootId];
    var i = 0;
    while (i < q.length) {
      final p = q[i++];
      final ch = await _withTimeout(
        _folders(careGroupId)
            .where("parentFolderId", isEqualTo: p)
            .get(),
      );
      for (final d in ch.docs) {
        if (all.add(d.id)) {
          q.add(d.id);
        }
      }
    }
    return all;
  }

  Future<String> createFolder(
    String careGroupId, {
    required String name,
    String parentFolderId = "",
  }) async {
    if (!_firebaseReady) {
      return "";
    }
    final t = name.trim();
    if (t.isEmpty) {
      throw ArgumentError("Enter a folder name.");
    }
    if (t.length > 200) {
      throw ArgumentError("Name is too long (200 characters max).");
    }
    final now = FieldValue.serverTimestamp();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError("Not signed in.");
    }
    final ref = _folders(careGroupId).doc();
    await _withTimeout(
      ref.set({
        "name": t,
        "parentFolderId": parentFolderId,
        "inTrash": false,
        "createdBy": uid,
        "createdAt": now,
        "updatedAt": now,
      }),
    );
    return ref.id;
  }

  Future<void> moveFolderTo(
    String careGroupId, {
    required String folderId,
    required String newParentFolderId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    if (folderId == newParentFolderId) {
      return;
    }
    if (newParentFolderId == folderId) {
      throw ArgumentError("A folder can’t be moved into itself.");
    }
    if (newParentFolderId.isNotEmpty) {
      final p = await _withTimeout(
        _folders(careGroupId).doc(newParentFolderId).get(),
      );
      if (!p.exists) {
        throw StateError("That folder no longer exists.");
      }
      final pData = LibraryFolder.fromDoc(
        p.id,
        p.data() ?? {},
      );
      if (pData.inTrash) {
        throw StateError("You can’t move a folder into Trash. Restore the destination first.");
      }
    }
    final selfTree = await _folderTreeIds(
      careGroupId,
      rootId: folderId,
    );
    if (newParentFolderId.isNotEmpty && selfTree.contains(newParentFolderId)) {
      throw ArgumentError("A folder can’t be moved inside one of its own sub-folders.");
    }
    final now = FieldValue.serverTimestamp();
    await _withTimeout(
      _folders(careGroupId).doc(folderId).update({
        "parentFolderId": newParentFolderId,
        "updatedAt": now,
      }),
    );
  }

  Future<void> moveFileTo(
    String careGroupId, {
    required String fileId,
    required String newFolderId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    if (newFolderId.isNotEmpty) {
      final p = await _withTimeout(
        _folders(careGroupId).doc(newFolderId).get(),
      );
      if (!p.exists) {
        throw StateError("That folder no longer exists.");
      }
      final f = LibraryFolder.fromDoc(
        p.id,
        p.data() ?? {},
      );
      if (f.inTrash) {
        throw StateError("You can’t move a file into Trash. Restore the folder or use Trash.");
      }
    }
    final now = FieldValue.serverTimestamp();
    await _withTimeout(
      _files(careGroupId).doc(fileId).update({
        "folderId": newFolderId,
        "updatedAt": now,
      }),
    );
  }

  Future<void> _trashFile(
    String careGroupId,
    String fileId,
  ) async {
    final now = FieldValue.serverTimestamp();
    await _withTimeout(
      _files(careGroupId).doc(fileId).update({
        "inTrash": true,
        "trashedAt": now,
        "updatedAt": now,
      }),
    );
  }

  /// Moves a file to Trash (no Storage delete, no Firestore delete).
  Future<void> trashFile(
    String careGroupId, {
    required String fileId,
  }) {
    if (!_firebaseReady) {
      return Future.value();
    }
    return _trashFile(careGroupId, fileId);
  }

  /// Moves a folder to Trash, including all nested folders and all files in that tree.
  Future<void> trashFolderRecursively(
    String careGroupId, {
    required String folderId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final ids = await _folderTreeIds(
      careGroupId,
      rootId: folderId,
    );
    final fileSnaps = await _withTimeout(
      _files(careGroupId).get(),
    );
    final now = FieldValue.serverTimestamp();
    const chunk = 400;
    var batch = FirebaseFirestore.instance.batch();
    var n = 0;
    for (final f in fileSnaps.docs) {
      final file = LibraryFile.fromDoc(
        f.id,
        f.data(),
      );
      if (file.inTrash) {
        continue;
      }
      final p = file.folderId;
      if (ids.contains(p)) {
        batch.set(
          _files(careGroupId).doc(f.id),
          {
            "inTrash": true,
            "trashedAt": now,
            "updatedAt": now,
          },
          SetOptions(merge: true),
        );
        n++;
        if (n >= chunk) {
          await _withTimeout(batch.commit());
          batch = FirebaseFirestore.instance.batch();
          n = 0;
        }
      }
    }
    for (final fid in ids) {
      batch.set(
        _folders(careGroupId).doc(fid),
        {
          "inTrash": true,
          "trashedAt": now,
          "updatedAt": now,
        },
        SetOptions(merge: true),
      );
      n++;
      if (n >= chunk) {
        await _withTimeout(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        n = 0;
      }
    }

    if (n > 0) {
      await _withTimeout(batch.commit());
    }
  }

  /// Restores a trashed file. If the containing folder is still in Trash, moves to the library root.
  Future<void> restoreFile(
    String careGroupId, {
    required String fileId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final s = await _withTimeout(
      _files(careGroupId).doc(fileId).get(),
    );
    if (!s.exists) {
      return;
    }
    var file = LibraryFile.fromDoc(
      s.id,
      s.data() ?? {},
    );
    if (!file.inTrash) {
      return;
    }
    var newFolder = file.folderId;
    if (newFolder.isNotEmpty) {
      final fd = await _withTimeout(
        _folders(careGroupId).doc(newFolder).get(),
      );
      if (!fd.exists) {
        newFolder = "";
      } else {
        final fData = LibraryFolder.fromDoc(
          fd.id,
          fd.data() ?? {},
        );
        if (fData.inTrash) {
          newFolder = "";
        }
      }
    }
    final now = FieldValue.serverTimestamp();
    await _withTimeout(
      _files(careGroupId).doc(fileId).update({
        "inTrash": false,
        "trashedAt": FieldValue.delete(),
        "folderId": newFolder,
        "updatedAt": now,
      }),
    );
  }

  /// Recursively restores a trashed folder, its trashed sub-folders, and trashed files that belong to the tree.
  Future<void> restoreFolderRecursively(
    String careGroupId, {
    required String folderId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final ids = await _folderTreeIds(
      careGroupId,
      rootId: folderId,
    );
    final fileSnaps = await _withTimeout(
      _files(careGroupId).get(),
    );
    final now = FieldValue.serverTimestamp();
    const chunk = 400;
    var batch = FirebaseFirestore.instance.batch();
    var n = 0;

    for (final fid in ids) {
      batch.set(
        _folders(careGroupId).doc(fid),
        {
          "inTrash": false,
          "trashedAt": FieldValue.delete(),
          "updatedAt": now,
        },
        SetOptions(merge: true),
      );
      n++;
      if (n >= chunk) {
        await _withTimeout(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        n = 0;
      }
    }
    for (final f in fileSnaps.docs) {
      final file = LibraryFile.fromDoc(
        f.id,
        f.data(),
      );
      if (!file.inTrash) {
        continue;
      }
      if (!ids.contains(file.folderId)) {
        continue;
      }
      batch.set(
        _files(careGroupId).doc(f.id),
        {
          "inTrash": false,
          "trashedAt": FieldValue.delete(),
          "updatedAt": now,
        },
        SetOptions(merge: true),
      );
      n++;
      if (n >= chunk) {
        await _withTimeout(batch.commit());
        batch = FirebaseFirestore.instance.batch();
        n = 0;
      }
    }
    if (n > 0) {
      await _withTimeout(batch.commit());
    }
  }

  Future<void> renameFolder(
    String careGroupId, {
    required String folderId,
    required String newName,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final t = newName.trim();
    if (t.isEmpty) {
      throw ArgumentError("Enter a folder name.");
    }
    if (t.length > 200) {
      throw ArgumentError("Name is too long (200 characters max).");
    }
    final now = FieldValue.serverTimestamp();
    await _withTimeout(
      _folders(careGroupId).doc(folderId).update({
        "name": t,
        "updatedAt": now,
      }),
    );
  }

  String? _contentTypeForExtension(String? ext) {
    if (ext == null) {
      return null;
    }
    final e = ext.toLowerCase().replaceAll(".", "");
    if (e == "pdf") return "application/pdf";
    if (e == "png") return "image/png";
    if (e == "jpg" || e == "jpeg") return "image/jpeg";
    if (e == "gif") return "image/gif";
    if (e == "webp") return "image/webp";
    if (e == "txt") return "text/plain";
    if (e == "html" || e == "htm") return "text/html";
    if (e == "doc") return "application/msword";
    if (e == "docx") {
      return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    }
    if (e == "xls") return "application/vnd.ms-excel";
    if (e == "xlsx") {
      return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    }
    if (e == "csv") return "text/csv";
    return null;
  }

  /// Uploads one file into the given folder; adds the Firestore row only after Storage succeeds.
  Future<void> uploadFile(
    String careGroupId, {
    String folderId = "",
    required PlatformFile file,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    if (folderId.isNotEmpty) {
      final fd = await _withTimeout(
        _folders(careGroupId).doc(folderId).get(),
      );
      if (!fd.exists) {
        throw StateError("That folder no longer exists.");
      }
      final fData = LibraryFolder.fromDoc(
        fd.id,
        fd.data() ?? {},
      );
      if (fData.inTrash) {
        throw StateError("You can’t upload into Trash. Choose another folder or restore it.");
      }
    }
    final bytes = await platform_file_read.readPlatformFileBytes(file);
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        "Could not read the file. Try choosing it again.",
      );
    }
    if (bytes.length > _maxBytes) {
      throw ArgumentError("Each file must be under 10 MB.");
    }
    final name = _safeFileName(file.name);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError("Not signed in.");
    }
    final docRef = _files(careGroupId).doc();
    final fileId = docRef.id;
    final storageRef = FirebaseStorage.instance.ref().child(
      "careGroups/$careGroupId/doc_library/$fileId/$name",
    );
    final ext = file.extension;
    final ct = _contentTypeForExtension(ext);
    if (ct != null) {
      await storageRef
          .putData(bytes, SettableMetadata(contentType: ct))
          .timeout(
            _uploadTimeout,
            onTimeout: () => throw TimeoutException(
              "Upload timed out. Check your connection and try again.",
              _uploadTimeout,
            ),
          );
    } else {
      await storageRef.putData(bytes).timeout(
        _uploadTimeout,
        onTimeout: () => throw TimeoutException(
          "Upload timed out. Check your connection and try again.",
          _uploadTimeout,
        ),
      );
    }
    final downloadUrl = await storageRef.getDownloadURL();
    final now = FieldValue.serverTimestamp();
    final m = <String, dynamic>{
      "displayName": name,
      "storagePath": storageRef.fullPath,
      "downloadUrl": downloadUrl,
      "sizeBytes": bytes.length,
      "folderId": folderId,
      "inTrash": false,
      "uploadedBy": uid,
      "uploadedAt": now,
      "updatedAt": now,
    };
    if (ct != null) {
      m["contentType"] = ct;
    }
    await _withTimeout(
      docRef.set(m),
    );
  }
}

