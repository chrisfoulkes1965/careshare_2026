import "package:cloud_firestore/cloud_firestore.dart";
import "package:equatable/equatable.dart";

/// Additional email address attached to a user profile (beyond the primary auth
/// email). Verification is performed server-side via the
/// `sendAlternateEmailVerification` / `confirmAlternateEmailVerification`
/// callable Cloud Functions; clients must not flip [verified] to true directly.
class AlternateEmail extends Equatable {
  const AlternateEmail({
    required this.address,
    this.verified = false,
    this.addedAt,
    this.verifiedAt,
    this.lastVerificationSentAt,
  });

  final String address;
  final bool verified;
  final DateTime? addedAt;
  final DateTime? verifiedAt;
  final DateTime? lastVerificationSentAt;

  /// Lower-case + trimmed canonical form used for comparisons / dedup.
  String get normalized => address.trim().toLowerCase();

  AlternateEmail copyWith({
    String? address,
    bool? verified,
    DateTime? addedAt,
    DateTime? verifiedAt,
    DateTime? lastVerificationSentAt,
  }) {
    return AlternateEmail(
      address: address ?? this.address,
      verified: verified ?? this.verified,
      addedAt: addedAt ?? this.addedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      lastVerificationSentAt:
          lastVerificationSentAt ?? this.lastVerificationSentAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "address": address.trim(),
      "verified": verified,
      if (addedAt != null) "addedAt": Timestamp.fromDate(addedAt!),
      if (verifiedAt != null) "verifiedAt": Timestamp.fromDate(verifiedAt!),
      if (lastVerificationSentAt != null)
        "lastVerificationSentAt": Timestamp.fromDate(lastVerificationSentAt!),
    };
  }

  static AlternateEmail? fromFirestore(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final addr = (raw["address"] as String?)?.trim() ?? "";
    if (addr.isEmpty) {
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

    return AlternateEmail(
      address: addr,
      verified: raw["verified"] == true,
      addedAt: ts(raw["addedAt"]),
      verifiedAt: ts(raw["verifiedAt"]),
      lastVerificationSentAt: ts(raw["lastVerificationSentAt"]),
    );
  }

  @override
  List<Object?> get props =>
      [address, verified, addedAt, verifiedAt, lastVerificationSentAt];
}
