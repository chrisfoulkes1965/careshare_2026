import "package:cloud_firestore/cloud_firestore.dart";
import "package:equatable/equatable.dart";

/// Additional phone number attached to a user profile.
///
/// SMS verification for alternate numbers is not yet wired (it requires a third
/// party SMS provider e.g. Twilio). Until that lands, [verified] stays `false`
/// and [verificationSkippedNonMobile] flags numbers the user explicitly marked
/// as non-mobile so the UI can label them differently from "needs verifying".
class AlternatePhone extends Equatable {
  const AlternatePhone({
    required this.number,
    this.label,
    this.verified = false,
    this.verificationSkippedNonMobile = false,
    this.addedAt,
    this.verifiedAt,
  });

  final String number;
  final String? label;
  final bool verified;
  final bool verificationSkippedNonMobile;
  final DateTime? addedAt;
  final DateTime? verifiedAt;

  /// Trimmed canonical form for comparisons (does not normalise punctuation).
  String get normalized => number.trim();

  AlternatePhone copyWith({
    String? number,
    String? label,
    bool? verified,
    bool? verificationSkippedNonMobile,
    DateTime? addedAt,
    DateTime? verifiedAt,
  }) {
    return AlternatePhone(
      number: number ?? this.number,
      label: label ?? this.label,
      verified: verified ?? this.verified,
      verificationSkippedNonMobile:
          verificationSkippedNonMobile ?? this.verificationSkippedNonMobile,
      addedAt: addedAt ?? this.addedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "number": number.trim(),
      if (label != null && label!.trim().isNotEmpty) "label": label!.trim(),
      "verified": verified,
      if (verificationSkippedNonMobile) "verificationSkippedNonMobile": true,
      if (addedAt != null) "addedAt": Timestamp.fromDate(addedAt!),
      if (verifiedAt != null) "verifiedAt": Timestamp.fromDate(verifiedAt!),
    };
  }

  static AlternatePhone? fromFirestore(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final n = (raw["number"] as String?)?.trim() ?? "";
    if (n.isEmpty) {
      return null;
    }
    DateTime? ts(Object? v) {
      if (v is Timestamp) {
        return v.toDate();
      }
      if (v is DateTime) {
        return v;
      }
      return null;
    }

    final lbl = (raw["label"] as String?)?.trim();
    return AlternatePhone(
      number: n,
      label: (lbl != null && lbl.isNotEmpty) ? lbl : null,
      verified: raw["verified"] == true,
      verificationSkippedNonMobile:
          raw["verificationSkippedNonMobile"] == true,
      addedAt: ts(raw["addedAt"]),
      verifiedAt: ts(raw["verifiedAt"]),
    );
  }

  @override
  List<Object?> get props => [
        number,
        label,
        verified,
        verificationSkippedNonMobile,
        addedAt,
        verifiedAt,
      ];
}
