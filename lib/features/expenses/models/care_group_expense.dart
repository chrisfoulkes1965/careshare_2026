import "package:cloud_firestore/cloud_firestore.dart";

/// Stored in Firestore as [expenseStatus]. Legacy documents omit it → treated as [approved].
abstract final class ExpenseClaimStatus {
  static const submitted = "submitted";
  static const approved = "approved";
  static const rejected = "rejected";
  static const paid = "paid";
}

/// `careGroups/{careGroupId}/expenses/{expenseId}`
final class CareGroupExpense {
  const CareGroupExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    required this.spentAt,
    this.category,
    this.payee,
    this.notes,
    this.receiptUrl,
    required this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.expenseStatus = ExpenseClaimStatus.approved,
    this.rejectionReason,
    this.reviewedAt,
    this.reviewedBy,
    this.paidAt,
    this.paidBy,
    this.paymentClaimId,
  });

  final String id;
  final String title;
  final double amount;
  final String currency;
  final DateTime spentAt;
  final String? category;
  final String? payee;
  final String? notes;

  /// Firebase Storage download URL for a receipt (image or PDF), if attached.
  final String? receiptUrl;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// [ExpenseClaimStatus] — omitted in Firestore historically means [ExpenseClaimStatus.approved].
  final String expenseStatus;
  final String? rejectionReason;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final DateTime? paidAt;
  final String? paidBy;
  final String? paymentClaimId;

  bool get isSubmitted => expenseStatus == ExpenseClaimStatus.submitted;
  bool get isApproved => expenseStatus == ExpenseClaimStatus.approved;
  bool get isRejected => expenseStatus == ExpenseClaimStatus.rejected;
  bool get isPaid => expenseStatus == ExpenseClaimStatus.paid;

  /// Submitter or finance staff may edit core fields before approval or pay.
  bool get canEditCoreFields =>
      expenseStatus == ExpenseClaimStatus.submitted ||
      expenseStatus == ExpenseClaimStatus.approved;

  static double _amount(dynamic v) {
    if (v is num) {
      return v.toDouble();
    }
    return 0;
  }

  static String _statusFromData(Map<String, dynamic> d) {
    final s = (d["expenseStatus"] as String?)?.trim();
    if (s == ExpenseClaimStatus.submitted ||
        s == ExpenseClaimStatus.approved ||
        s == ExpenseClaimStatus.rejected ||
        s == ExpenseClaimStatus.paid) {
      return s!;
    }
    return ExpenseClaimStatus.approved;
  }

  static CareGroupExpense fromDoc(
    String id,
    Map<String, dynamic> d,
  ) {
    final spent = d["spentAt"];
    final created = d["createdAt"];
    final updated = d["updatedAt"];
    final reviewed = d["reviewedAt"];
    final paid = d["paidAt"];
    return CareGroupExpense(
      id: id,
      title: (d["title"] as String?)?.trim() ?? "Expense",
      amount: _amount(d["amount"]),
      currency: (d["currency"] as String?)?.trim().toUpperCase() ?? "GBP",
      spentAt: spent is Timestamp ? spent.toDate() : DateTime.now(),
      category: (d["category"] as String?)?.trim(),
      payee: (d["payee"] as String?)?.trim(),
      notes: (d["notes"] as String?)?.trim(),
      receiptUrl: (d["receiptUrl"] as String?)?.trim(),
      createdBy: (d["createdBy"] as String?) ?? "",
      createdAt: created is Timestamp ? created.toDate() : null,
      updatedAt: updated is Timestamp ? updated.toDate() : null,
      expenseStatus: _statusFromData(d),
      rejectionReason: (d["rejectionReason"] as String?)?.trim(),
      reviewedAt: reviewed is Timestamp ? reviewed.toDate() : null,
      reviewedBy: (d["reviewedBy"] as String?)?.trim(),
      paidAt: paid is Timestamp ? paid.toDate() : null,
      paidBy: (d["paidBy"] as String?)?.trim(),
      paymentClaimId: (d["paymentClaimId"] as String?)?.trim(),
    );
  }
}
