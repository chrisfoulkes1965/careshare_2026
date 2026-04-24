import "package:cloud_firestore/cloud_firestore.dart";

import "../../setup_wizard/models/setup_models.dart";

/// Resolves the active careGroup’s pathway selection and (optionally) system pathway docs.
class PathwaysRepository {
  PathwaysRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  bool get isAvailable => _firebaseReady;

  /// Labels for the careGroup’s `pathwayIds` using the in-app catalog (wizard source of truth).
  Future<CareGroupPathwaysSummary> getCareGroupPathways(String careGroupId) async {
    if (!_firebaseReady) {
      return const CareGroupPathwaysSummary(careGroupName: null, selected: [], system: []);
    }
    final doc = await FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .get();
    if (!doc.exists) {
      return const CareGroupPathwaysSummary(careGroupName: null, selected: [], system: []);
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

    return CareGroupPathwaysSummary(
      careGroupName: name,
      selected: selected,
      system: system,
    );
  }

  CarePathwayOption _fallbackOption(String id) {
    return CarePathwayOption(
      id: id,
      title: id,
      description: "This pathway id is on your careGroup document; add a matching title in the catalog if needed.",
    );
  }
}

final class CareGroupPathwaysSummary {
  const CareGroupPathwaysSummary({
    required this.careGroupName,
    required this.selected,
    required this.system,
  });

  final String? careGroupName;
  final List<CarePathwayOption> selected;
  final List<CarePathwayOption> system;
}
