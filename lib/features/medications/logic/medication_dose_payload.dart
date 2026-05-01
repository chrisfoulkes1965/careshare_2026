/// Parses `dose|careGroupId|commaMedIds|slotKey` from notification payloads (slot segment optional).
final class MedicationDosePayload {
  const MedicationDosePayload({
    required this.careGroupId,
    required this.medicationIds,
    this.slotKey = "",
  });

  final String careGroupId;
  final List<String> medicationIds;

  /// Local schedule occurrence key, e.g. `2026-05-02_t_8_30`.
  final String slotKey;

  static MedicationDosePayload? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (!raw.startsWith("dose|")) {
      return null;
    }
    final parts = raw.split("|");
    if (parts.length < 3) {
      return null;
    }
    final cg = parts[1].trim();
    final ids = parts[2]
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cg.isEmpty || ids.isEmpty) {
      return null;
    }
    final sk = parts.length >= 4 ? parts.sublist(3).join("|").trim() : "";
    return MedicationDosePayload(
      careGroupId: cg,
      medicationIds: ids,
      slotKey: sk,
    );
  }
}
