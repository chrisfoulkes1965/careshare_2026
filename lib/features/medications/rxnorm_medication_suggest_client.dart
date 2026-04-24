import "dart:convert";

import "package:http/http.dart" as http;

/// Suggests medication display names using the U.S. National Library of Medicine
/// [RxNorm](https://www.nlm.nih.gov/research/umls/rxnorm/index.html) API (no API key).
///
/// Data is US-oriented and for convenience only; users must still match their own label.
final class RxNormMedicationSuggestClient {
  const RxNormMedicationSuggestClient();

  static const _host = "rxnav.nlm.nih.gov";
  static const _path = "/REST/approximateTerm.json";

  /// Returns unique names (trimmed), in API order, up to [maxResults].
  Future<List<String>> suggest(String term, {int maxResults = 15}) async {
    final t = term.trim();
    if (t.length < 2) {
      return const [];
    }
    final uri = Uri.https(_host, _path, {
      "term": t,
      "maxEntries": "25",
    });
    final response = await http.get(uri).timeout(
          const Duration(seconds: 12),
        );
    if (response.statusCode != 200) {
      return const [];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }
    final group = decoded["approximateGroup"];
    if (group is! Map<String, dynamic>) {
      return const [];
    }
    final raw = group["candidate"];
    final candidates = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          candidates.add(Map<String, dynamic>.from(e));
        }
      }
    } else if (raw is Map) {
      candidates.add(Map<String, dynamic>.from(raw));
    }
    final seen = <String>{};
    final out = <String>[];
    for (final c in candidates) {
      final n = c["name"];
      if (n is! String) {
        continue;
      }
      final name = n.trim();
      if (name.isEmpty) {
        continue;
      }
      if (!seen.add(name.toLowerCase())) {
        continue;
      }
      out.add(name);
      if (out.length >= maxResults) {
        break;
      }
    }
    return out;
  }
}
