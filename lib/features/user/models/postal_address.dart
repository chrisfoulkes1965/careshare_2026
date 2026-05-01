import "package:equatable/equatable.dart";

/// User-supplied postal address, optional. Stored as a nested map on `users/{uid}`.
class PostalAddress extends Equatable {
  const PostalAddress({
    this.line1,
    this.line2,
    this.city,
    this.region,
    this.postalCode,
    this.country,
  });

  final String? line1;
  final String? line2;
  final String? city;
  final String? region;
  final String? postalCode;
  final String? country;

  bool get isEmpty =>
      _isBlank(line1) &&
      _isBlank(line2) &&
      _isBlank(city) &&
      _isBlank(region) &&
      _isBlank(postalCode) &&
      _isBlank(country);

  bool get isNotEmpty => !isEmpty;

  static bool _isBlank(String? s) => s == null || s.trim().isEmpty;

  /// Multi-line summary for read-only display.
  String formatted() {
    final parts = <String>[
      if (!_isBlank(line1)) line1!.trim(),
      if (!_isBlank(line2)) line2!.trim(),
      if (!_isBlank(city) || !_isBlank(region) || !_isBlank(postalCode))
        [
          if (!_isBlank(city)) city!.trim(),
          if (!_isBlank(region)) region!.trim(),
          if (!_isBlank(postalCode)) postalCode!.trim(),
        ].join(", "),
      if (!_isBlank(country)) country!.trim(),
    ];
    return parts.join("\n");
  }

  PostalAddress copyWith({
    String? line1,
    String? line2,
    String? city,
    String? region,
    String? postalCode,
    String? country,
  }) {
    return PostalAddress(
      line1: line1 ?? this.line1,
      line2: line2 ?? this.line2,
      city: city ?? this.city,
      region: region ?? this.region,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (!_isBlank(line1)) "line1": line1!.trim(),
      if (!_isBlank(line2)) "line2": line2!.trim(),
      if (!_isBlank(city)) "city": city!.trim(),
      if (!_isBlank(region)) "region": region!.trim(),
      if (!_isBlank(postalCode)) "postalCode": postalCode!.trim(),
      if (!_isBlank(country)) "country": country!.trim(),
    };
  }

  static PostalAddress? fromFirestore(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    String? str(String key) {
      final v = raw[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final a = PostalAddress(
      line1: str("line1"),
      line2: str("line2"),
      city: str("city"),
      region: str("region"),
      postalCode: str("postalCode"),
      country: str("country"),
    );
    return a.isEmpty ? null : a;
  }

  @override
  List<Object?> get props => [line1, line2, city, region, postalCode, country];
}
