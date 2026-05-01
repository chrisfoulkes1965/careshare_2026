import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:file_picker/file_picker.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";

import "../models/care_group_expense.dart"
    show CareGroupExpense, ExpenseClaimStatus;
import "platform_file_read_io.dart" if (dart.library.html) "platform_file_read_web.dart" as platform_file_read;

class ExpensesRepository {
  ExpensesRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  static const int _maxReceiptBytes = 10 * 1024 * 1024;
  static const Duration _uploadTimeout = Duration(minutes: 2);
  static const Duration _writeTimeout = Duration(seconds: 60);
  static const Duration _downloadUrlTimeout = Duration(seconds: 45);

  bool get isAvailable => _firebaseReady;

  CollectionReference<Map<String, dynamic>> _expenses(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("expenses");
  }

  DocumentReference<Map<String, dynamic>> _expensePaymentClaimDoc(
    String careGroupId,
    String claimId,
  ) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("expensePaymentClaims")
        .doc(claimId);
  }

  String _safeFileName(String name) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
    if (n.isEmpty) n = "file";
    return n.length > 200 ? n.substring(0, 200) : n;
  }

  Future<void> _tryDeleteStorageFile(String downloadUrl) async {
    try {
      await FirebaseStorage.instance.refFromURL(downloadUrl).delete();
    } catch (_) {
      // Best-effort cleanup; URL may be invalid or already removed.
    }
  }

  Stream<List<CareGroupExpense>> watchExpenses(String careGroupId) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _expenses(careGroupId)
        .orderBy("spentAt", descending: true)
        .limit(300)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => CareGroupExpense.fromDoc(d.id, d.data()))
              .toList(),
        );
  }

  Future<String> addExpense({
    required String careGroupId,
    required String title,
    required double amount,
    required String currency,
    required DateTime spentAt,
    String? category,
    String? payee,
    String? notes,
  }) async {
    if (!_firebaseReady) {
      return "";
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final t = title.trim();
    if (t.isEmpty) {
      throw ArgumentError("Title is required.");
    }
    if (amount <= 0) {
      throw ArgumentError("Amount must be greater than zero.");
    }
    final c = currency.trim().toUpperCase();
    if (c.isEmpty) {
      throw ArgumentError("Currency is required.");
    }
    final data = <String, dynamic>{
      "title": t,
      "amount": amount,
      "currency": c,
      "spentAt": Timestamp.fromDate(spentAt),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
      "expenseStatus": "submitted",
    };
    final cat = category?.trim();
    if (cat != null && cat.isNotEmpty) {
      data["category"] = cat;
    }
    final p = payee?.trim();
    if (p != null && p.isNotEmpty) {
      data["payee"] = p;
    }
    final n = notes?.trim();
    if (n != null && n.isNotEmpty) {
      data["notes"] = n;
    }
    final ref = await _expenses(careGroupId).add(data);
    return ref.id;
  }

  /// Uploads [file] to Storage and sets [receiptUrl] on the expense document.
  /// Replaces any previous receipt URL; the old Storage object is removed when possible.
  Future<void> uploadAndSetReceipt({
    required String careGroupId,
    required String expenseId,
    required PlatformFile file,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    String? oldUrl;
    final existing = await _expenses(careGroupId).doc(expenseId).get();
    if (existing.exists) {
      oldUrl = (existing.data()?["receiptUrl"] as String?)?.trim();
    }
    final bytes = await platform_file_read.readPlatformFileBytes(file);
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        "Could not read the receipt file. Try choosing it again.",
      );
    }
    if (bytes.length > _maxReceiptBytes) {
      throw ArgumentError("Receipt must be under 10 MB.");
    }
    final name = _safeFileName(file.name);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef = FirebaseStorage.instance
        .ref()
        .child("careGroups/$careGroupId/expense_receipts/$expenseId/${stamp}_$name");
    await storageRef.putData(bytes).timeout(
      _uploadTimeout,
      onTimeout: () => throw TimeoutException(
        "Upload timed out. Check your connection and try again.",
        _uploadTimeout,
      ),
    );
    final url = await storageRef.getDownloadURL().timeout(
      _downloadUrlTimeout,
      onTimeout: () => throw TimeoutException(
        "Could not get download link after upload.",
        _downloadUrlTimeout,
      ),
    );
    await _expenses(careGroupId)
        .doc(expenseId)
        .update({
          "receiptUrl": url,
          "updatedAt": FieldValue.serverTimestamp(),
        })
        .timeout(
          _writeTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not save receipt link. Check your connection and try again.",
            _writeTimeout,
          ),
        );
    final o = oldUrl;
    if (o != null && o.isNotEmpty && o != url) {
      await _tryDeleteStorageFile(o);
    }
  }

  Future<void> clearReceiptUrl({
    required String careGroupId,
    required String expenseId,
    String? previousDownloadUrl,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    await _expenses(careGroupId)
        .doc(expenseId)
        .update({
          "receiptUrl": FieldValue.delete(),
          "updatedAt": FieldValue.serverTimestamp(),
        })
        .timeout(
          _writeTimeout,
          onTimeout: () => throw TimeoutException(
            "Could not remove receipt. Check your connection and try again.",
            _writeTimeout,
          ),
        );
    final u = previousDownloadUrl?.trim();
    if (u != null && u.isNotEmpty) {
      await _tryDeleteStorageFile(u);
    }
  }

  Future<void> updateExpense({
    required String careGroupId,
    required String expenseId,
    required String title,
    required double amount,
    required String currency,
    required DateTime spentAt,
    String? category,
    String? payee,
    String? notes,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final t = title.trim();
    if (t.isEmpty) {
      throw ArgumentError("Title is required.");
    }
    if (amount <= 0) {
      throw ArgumentError("Amount must be greater than zero.");
    }
    final c = currency.trim().toUpperCase();
    final data = <String, dynamic>{
      "title": t,
      "amount": amount,
      "currency": c,
      "spentAt": Timestamp.fromDate(spentAt),
      "updatedAt": FieldValue.serverTimestamp(),
    };
    final cat = category?.trim();
    if (cat == null || cat.isEmpty) {
      data["category"] = FieldValue.delete();
    } else {
      data["category"] = cat;
    }
    final p = payee?.trim();
    if (p == null || p.isEmpty) {
      data["payee"] = FieldValue.delete();
    } else {
      data["payee"] = p;
    }
    final n = notes?.trim();
    if (n == null || n.isEmpty) {
      data["notes"] = FieldValue.delete();
    } else {
      data["notes"] = n;
    }
    await _expenses(careGroupId).doc(expenseId).update(data);
  }

  Future<void> deleteExpense({
    required String careGroupId,
    required String expenseId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final snap = await _expenses(careGroupId).doc(expenseId).get();
    final url = (snap.data()?["receiptUrl"] as String?)?.trim();
    if (url != null && url.isNotEmpty) {
      await _tryDeleteStorageFile(url);
    }
    await _expenses(careGroupId).doc(expenseId).delete();
  }

  Future<void> approveExpense({
    required String careGroupId,
    required String expenseId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final ts = Timestamp.now();
    await _expenses(careGroupId).doc(expenseId).update({
      "expenseStatus": ExpenseClaimStatus.approved,
      "reviewedAt": ts,
      "reviewedBy": uid,
      "rejectionReason": FieldValue.delete(),
      "updatedAt": FieldValue.serverTimestamp(),
    }).timeout(
      _writeTimeout,
      onTimeout: () => throw TimeoutException(
        "Could not approve expense.",
        _writeTimeout,
      ),
    );
  }

  Future<void> rejectExpense({
    required String careGroupId,
    required String expenseId,
    required String rejectionReason,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final reason = rejectionReason.trim();
    if (reason.isEmpty) {
      throw ArgumentError("A rejection reason is required.");
    }
    final ts = Timestamp.now();
    await _expenses(careGroupId).doc(expenseId).update({
      "expenseStatus": ExpenseClaimStatus.rejected,
      "rejectionReason": reason.length > 2000 ? reason.substring(0, 2000) : reason,
      "reviewedAt": ts,
      "reviewedBy": uid,
      "updatedAt": FieldValue.serverTimestamp(),
    }).timeout(
      _writeTimeout,
      onTimeout: () => throw TimeoutException(
        "Could not reject expense.",
        _writeTimeout,
      ),
    );
  }

  /// Marks several **approved** expenses as paid in one claim; creates [expensePaymentClaims] doc for email.
  /// All selected expenses must share the same [createdBy] (payee) and currency.
  Future<String> markExpensesPaid({
    required String careGroupId,
    required List<String> expenseIds,
  }) async {
    if (!_firebaseReady) {
      return "";
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    if (expenseIds.isEmpty) {
      throw ArgumentError("Select at least one expense.");
    }
    final uniqueIds = expenseIds.toSet().toList();
    final expenses = <CareGroupExpense>[];
    for (final id in uniqueIds) {
      final snap = await _expenses(careGroupId).doc(id).get();
      if (!snap.exists || snap.data() == null) {
        throw StateError("Expense not found: $id");
      }
      expenses.add(CareGroupExpense.fromDoc(id, snap.data()!));
    }
    String? payeeUid;
    String? currency;
    var total = 0.0;
    final titles = <String>[];
    for (final e in expenses) {
      if (e.expenseStatus != ExpenseClaimStatus.approved) {
        throw StateError(
          "Only approved expenses can be paid (${e.title}).",
        );
      }
      payeeUid ??= e.createdBy;
      if (e.createdBy != payeeUid) {
        throw ArgumentError(
          "Selected expenses must belong to the same member (same submitter).",
        );
      }
      currency ??= e.currency;
      if (e.currency != currency) {
        throw ArgumentError(
          "Selected expenses must use the same currency.",
        );
      }
      total += e.amount;
      titles.add(e.title);
    }
    if (payeeUid == null || payeeUid.isEmpty) {
      throw StateError("Missing submitter on expense.");
    }
    final paymentClaimId =
        "pay_${DateTime.now().millisecondsSinceEpoch}_${uid.hashCode.abs()}";
    final safeClaimId = paymentClaimId.length > 128
        ? paymentClaimId.substring(0, 128)
        : paymentClaimId;
    var preview = titles.take(25).join("; ");
    if (titles.length > 25) {
      preview = "$preview; …";
    }
    if (preview.length > 2000) {
      preview = preview.substring(0, 2000);
    }
    final ts = Timestamp.now();
    final batch = FirebaseFirestore.instance.batch();
    batch.set(_expensePaymentClaimDoc(careGroupId, safeClaimId), {
      "payeeUid": payeeUid,
      "expenseIds": uniqueIds,
      "currency": currency,
      "totalAmount": total,
      "paidBy": uid,
      "paidAt": ts,
      "expenseTitlePreview": preview,
    });
    for (final e in expenses) {
      batch.update(_expenses(careGroupId).doc(e.id), {
        "expenseStatus": ExpenseClaimStatus.paid,
        "paidAt": ts,
        "paidBy": uid,
        "paymentClaimId": safeClaimId,
        "updatedAt": FieldValue.serverTimestamp(),
      });
    }
    await batch.commit().timeout(
      _writeTimeout,
      onTimeout: () => throw TimeoutException(
        "Could not record payment.",
        _writeTimeout,
      ),
    );
    return safeClaimId;
  }
}
