import "package:cloud_firestore/cloud_firestore.dart";

import "../../setup_wizard/models/setup_models.dart";

/// Resolves the active household’s pathway selection and (optionally) system pathway docs.
class PathwaysRepository {
  PathwaysRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  /// Labels for the household’s `pathwayIds` using the in-app catalog (wizard source of truth).
  Future<HouseholdPathwaysSummary> getHouseholdPathways(String householdId) async {
    if (!_firebaseReady) {
      return const HouseholdPathwaysSummary(householdName: null, selected: [], system: []);
    }
    final doc = await FirebaseFirestore.instance
        .collection("households")
        .doc(householdId)
        .get();
    if (!doc.exists) {
      return const HouseholdPathwaysSummary(householdName: null, selected: [], system: []);
    }
    final data = doc.data() ?? {};
    final name = (data["name"] as String?)?.trim();
    final ids = (data["pathwayIds"] as List?)?.cast<dynamic>().map((e) => e.toString()).toList() ?? <String>[];
    final byId = {for (final o in SetupPathways.all) o.id: o};
    final selected = ids.map((id) => byId[id] ?? _fallbackOption(id)).toList();

    var system = <CarePathwayOption>[];
    try {
      final systemSnap = await FirebaseFirestore.instance
          .collection("carePathways")
          .where("system", isEqualTo: true)
          .limit(50)
          .get();
      for (final d in systemSnap.docs) {
        final m = d.data();
        if (m["title"] is! String) continue;
        system.add(
          CarePathwayOption(
            id: d.id,
            title: m["title"] as String,
            description: (m["description"] as String?)?.trim() ?? "",
          ),
        );
      }
    } catch (_) {
      // Query may need an index or carePathways may be empty; selection still works.
      system = [];
    }

    return HouseholdPathwaysSummary(
      householdName: name,
      selected: selected,
      system: system,
    );
  }

  CarePathwayOption _fallbackOption(String id) {
    return CarePathwayOption(
      id: id,
      title: id,
      description: "This pathway id is on your household document; add a matching title in the catalog if needed.",
    );
  }
}

final class HouseholdPathwaysSummary {
  const HouseholdPathwaysSummary({
    required this.householdName,
    required this.selected,
    required this.system,
  });

  final String? householdName;
  final List<CarePathwayOption> selected;
  final List<CarePathwayOption> system;
}
