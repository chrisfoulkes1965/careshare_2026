import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:file_picker/file_picker.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../models/care_group_task.dart";
import "platform_file_read_io.dart" if (dart.library.html) "platform_file_read_web.dart" as platform_file_read;

class TaskRepository {
  TaskRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  static const int _maxAttachmentCount = 5;
  static const int _maxBytes = 10 * 1024 * 1024;
  static const Duration _uploadTimeout = Duration(minutes: 2);
  static const Duration _writeTimeout = Duration(seconds: 60);
  static const Duration _downloadUrlTimeout = Duration(seconds: 45);

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _tasks(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("tasks");
  }

  String _safeFileName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
    if (n.isEmpty) n = "file";
    return n.length > 200 ? n.substring(0, 200) : n;
  }

  Stream<List<CareGroupTask>> watchTasks(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _tasks(careGroupId)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map(CareGroupTask.fromDoc).toList(),
        );
  }

  Future<void> _uploadAndMergeAttachmentUrls({
    required String careGroupId,
    required String taskId,
    required List<PlatformFile> files,
  }) async {
    if (files.isEmpty) return;
    final root = FirebaseStorage.instance.ref().child("careGroups/$careGroupId/task_attachments/$taskId");
    final urls = <String>[];
    for (final f in files) {
      final name = _safeFileName(f.name);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ref = root.child("${stamp}_$name");
      final bytes = await platform_file_read.readPlatformFileBytes(f);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      if (bytes.length > _maxBytes) {
        throw ArgumentError("Each file must be under 10 MB.");
      }
      await ref.putData(bytes).timeout(
        _uploadTimeout,
        onTimeout: () => throw TimeoutException(
          "Upload timed out. Check your connection and try again.",
          _uploadTimeout,
        ),
      );
      urls.add(
        await ref.getDownloadURL().timeout(
          _downloadUrlTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not get download link after upload.",
            _downloadUrlTimeout,
          ),
        ),
      );
    }
    if (urls.isEmpty && files.isNotEmpty) {
      throw StateError(
        "Could not read any files to upload. Try choosing the files again.",
      );
    }
    if (urls.isEmpty) {
      return;
    }
    await _tasks(careGroupId)
        .doc(taskId)
        .update({
          "attachmentUrls": FieldValue.arrayUnion(urls),
        })
        .timeout(
          _writeTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not update task attachments. Check your connection and try again.",
            _writeTimeout,
          ),
        );
  }

  /// Creates a task and uploads [attachments] into Storage, then appends [attachmentUrls].

  Future<String> addTask({
    required String careGroupId,
    required String title,
    String? assignedTo,
    String notes = '',
    DateTime? dueAt,
    List<PlatformFile> attachments = const [],
  }) async {
    if (!_firebaseReady) {
      return '';
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError("Title is required.");
    }
    if (attachments.length > _maxAttachmentCount) {
      throw ArgumentError("At most $_maxAttachmentCount attachments per task.");
    }
    for (final f in attachments) {
      if (f.size > _maxBytes) {
        throw ArgumentError("Each file must be under 10 MB.");
      }
    }

    final data = <String, dynamic>{
      "title": trimmed,
      "status": "open",
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    };
    if (notes.trim().isNotEmpty) {
      data["notes"] = notes.trim();
    }
    if (dueAt != null) {
      data["dueAt"] = Timestamp.fromDate(dueAt);
    }
    if (assignedTo != null && assignedTo.isNotEmpty) {
      data["assignedTo"] = assignedTo;
    }
    if (attachments.isNotEmpty) {
      data["attachmentUrls"] = <String>[];
    }

    final ref = await _tasks(careGroupId)
        .add(data)
        .timeout(
          _writeTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not create the task in time. Check your connection and try again.",
            _writeTimeout,
          ),
        );
    final id = ref.id;
    if (attachments.isNotEmpty) {
      await _uploadAndMergeAttachmentUrls(
        careGroupId: careGroupId,
        taskId: id,
        files: attachments,
      );
    }
    return id;
  }

  /// Updates text fields; merges [newAttachments] with existing [attachmentUrls].

  Future<void> updateTask({
    required String careGroupId,
    required String taskId,
    required String title,
    required String notes,
    DateTime? dueAt,
    String? assignedTo,
    List<PlatformFile> newAttachments = const [],
  }) async {
    if (!_firebaseReady) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError("Title is required.");
    }
    if (newAttachments.length > _maxAttachmentCount) {
      throw ArgumentError("At most $_maxAttachmentCount new attachments at once.");
    }
    for (final f in newAttachments) {
      if (f.size > _maxBytes) {
        throw ArgumentError("Each file must be under 10 MB.");
      }
    }

    final patch = <String, dynamic>{"title": trimmed};
    if (notes.trim().isEmpty) {
      patch["notes"] = FieldValue.delete();
    } else {
      patch["notes"] = notes.trim();
    }
    if (dueAt != null) {
      patch["dueAt"] = Timestamp.fromDate(dueAt);
    } else {
      patch["dueAt"] = FieldValue.delete();
    }
    if (assignedTo != null && assignedTo.isNotEmpty) {
      patch["assignedTo"] = assignedTo;
    } else {
      patch["assignedTo"] = FieldValue.delete();
    }

    await _tasks(careGroupId)
        .doc(taskId)
        .update(patch)
        .timeout(
          _writeTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not update the task in time. Check your connection and try again.",
            _writeTimeout,
          ),
        );
    if (newAttachments.isNotEmpty) {
      await _uploadAndMergeAttachmentUrls(
        careGroupId: careGroupId,
        taskId: taskId,
        files: newAttachments,
      );
    }
  }

  /// Toggle done/open; must not change [createdBy] (rules require it to stay the same on update).

  Future<void> setTaskDone({
    required String careGroupId,
    required String taskId,
    required bool done,
  }) async {
    if (!_firebaseReady) return;
    await _tasks(careGroupId)
        .doc(taskId)
        .update({
          "status": done ? "done" : "open",
        })
        .timeout(
          _writeTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not update task status. Check your connection and try again.",
            _writeTimeout,
          ),
        );
  }

  Future<void> deleteTask({
    required String careGroupId,
    required String taskId,
  }) async {
    if (!_firebaseReady) return;
    await _tasks(careGroupId)
        .doc(taskId)
        .delete()
        .timeout(
          _writeTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not delete the task. Check your connection and try again.",
            _writeTimeout,
          ),
        );
  }
}
