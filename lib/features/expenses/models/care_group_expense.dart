import "package:cloud_firestore/cloud_firestore.dart";

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

  static double _amount(dynamic v) {
    if (v is num) {
      return v.toDouble();
    }
    return 0;
  }

  static CareGroupExpense fromDoc(
    String id,
    Map<String, dynamic> d,
  ) {
    final spent = d["spentAt"];
    final created = d["createdAt"];
    final updated = d["updatedAt"];
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
    );
  }
}
