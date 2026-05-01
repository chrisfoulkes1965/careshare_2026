import "package:equatable/equatable.dart";

/// Bank / payout details for expense reimbursement, stored on `users/{uid}.expensePaymentDetails`.
final class ExpensePaymentDetails extends Equatable {
  const ExpensePaymentDetails({
    required this.accountHolderName,
    this.sortCode,
    this.accountNumber,
    this.iban,
    this.bic,
  });

  /// Name on the account (must match bank records).
  final String accountHolderName;

  /// UK-style sort code (e.g. 12-34-56). Optional if [iban] is set.
  final String? sortCode;

  /// UK-style account number. Optional if [iban] is set.
  final String? accountNumber;

  /// International IBAN. Optional if [sortCode] and [accountNumber] are set.
  final String? iban;

  /// BIC / SWIFT — optional.
  final String? bic;

  static String _norm(String? s) => (s ?? "").trim();

  static String? _normNullable(String? s) {
    final t = _norm(s);
    return t.isEmpty ? null : t;
  }

  /// Normalised IBAN without spaces, upper case.
  static String? normalisedIban(String? raw) {
    final t = _norm(raw).replaceAll(RegExp(r"\s+"), "").toUpperCase();
    return t.isEmpty ? null : t;
  }

  /// Digits only for UK account number comparison / storage display.
  static String? normalisedUkAccount(String? raw) {
    final digits = _norm(raw).replaceAll(RegExp(r"\D"), "");
    return digits.isEmpty ? null : digits;
  }

  /// Sort code with optional dashes stripped to digits only for length checks.
  static String? normalisedSortCode(String? raw) {
    final digits = _norm(raw).replaceAll(RegExp(r"\D"), "");
    return digits.isEmpty ? null : digits;
  }

  bool get isComplete {
    final holder = _norm(accountHolderName);
    if (holder.length < 2) {
      return false;
    }
    final ib = normalisedIban(iban);
    if (ib != null && ib.length >= 8 && ib.length <= 34) {
      return true;
    }
    final sort = normalisedSortCode(sortCode);
    final acct = normalisedUkAccount(accountNumber);
    return sort != null &&
        sort.length >= 4 &&
        sort.length <= 16 &&
        acct != null &&
        acct.length >= 4 &&
        acct.length <= 18;
  }

  Map<String, dynamic> toFirestore() {
    final out = <String, dynamic>{
      "accountHolderName": _norm(accountHolderName),
    };
    final sc = normalisedSortCode(sortCode);
    final an = normalisedUkAccount(accountNumber);
    final ib = normalisedIban(iban);
    final bc = _normNullable(bic)?.toUpperCase();
    if (sc != null) {
      out["sortCode"] = sc;
    }
    if (an != null) {
      out["accountNumber"] = an;
    }
    if (ib != null) {
      out["iban"] = ib;
    }
    if (bc != null) {
      out["bic"] = bc.length > 20 ? bc.substring(0, 20) : bc;
    }
    return out;
  }

  static ExpensePaymentDetails? fromFirestore(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final holder = _norm(m["accountHolderName"] as String?);
    if (holder.isEmpty) {
      return null;
    }
    return ExpensePaymentDetails(
      accountHolderName: holder,
      sortCode: m["sortCode"] as String?,
      accountNumber: m["accountNumber"] as String?,
      iban: m["iban"] as String?,
      bic: m["bic"] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [accountHolderName, sortCode, accountNumber, iban, bic];
}
