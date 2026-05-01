import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../cubit/medications_cubit.dart";
import "../models/care_group_medication.dart";

/// Bulk count screen: enter the doses-on-hand for every medication at once.
///
/// Empty input means "not set" — falls back to the implicit 28-day estimate
/// elsewhere in the app. Only changed rows are sent to Firestore on save.
class MedicationStockTakeSheet extends StatefulWidget {
  const MedicationStockTakeSheet({super.key, required this.medications});

  final List<CareGroupMedication> medications;

  static Future<void> show(
    BuildContext context, {
    required List<CareGroupMedication> medications,
  }) {
    if (medications.isEmpty) {
      return Future.value();
    }
    final cubit = context.read<MedicationsCubit>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      showDragHandle: true,
      builder: (ctx) => BlocProvider<MedicationsCubit>.value(
        value: cubit,
        child: MedicationStockTakeSheet(medications: medications),
      ),
    );
  }

  @override
  State<MedicationStockTakeSheet> createState() => _MedicationStockTakeSheetState();
}

class _MedicationStockTakeSheetState extends State<MedicationStockTakeSheet> {
  late final List<_StockTakeRow> _rows;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final sorted = [...widget.medications]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _rows = sorted
        .map(
          (m) => _StockTakeRow(
            medication: m,
            controller: TextEditingController(
              text: m.quantityOnHand?.toString() ?? "",
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  /// Returns parsed entries (medId -> int? where null means clear) or `null`
  /// when validation fails.
  Map<String, int?>? _collectChanges() {
    final out = <String, int?>{};
    for (final r in _rows) {
      final raw = r.controller.text.trim();
      int? parsed;
      if (raw.isNotEmpty) {
        final p = int.tryParse(raw);
        if (p == null) {
          setState(() => _error = "“${r.medication.name}”: enter a whole number or leave blank.");
          return null;
        }
        if (p < 0) {
          setState(() => _error = "“${r.medication.name}”: doses on hand cannot be negative.");
          return null;
        }
        parsed = p;
      }
      final current = r.medication.quantityOnHand;
      final changed = parsed != current;
      if (changed) {
        out[r.medication.id] = parsed;
      }
    }
    return out;
  }

  Future<void> _onSave() async {
    if (_saving) {
      return;
    }
    setState(() => _error = null);
    final changes = _collectChanges();
    if (changes == null) {
      return;
    }
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<MedicationsCubit>().applyStockTake(changes);
      if (!mounted) {
        return;
      }
      final n = changes.length;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 1 ? "Updated stock for 1 medication." : "Updated stock for $n medications.",
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  "Stock take",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "Count what you have on hand for each medication and enter it below. "
                  "Leave a row blank to fall back to the 28-day estimate.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _StockTakeTile(
                    row: _rows[i],
                    enabled: !_saving,
                    onCleared: () {
                      setState(() {
                        _rows[i].controller.clear();
                      });
                    },
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _onSave,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text("Save counts"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockTakeRow {
  _StockTakeRow({required this.medication, required this.controller});

  final CareGroupMedication medication;
  final TextEditingController controller;
}

class _StockTakeTile extends StatelessWidget {
  const _StockTakeTile({
    required this.row,
    required this.enabled,
    required this.onCleared,
  });

  final _StockTakeRow row;
  final bool enabled;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final m = row.medication;
    final current = m.quantityOnHand;
    final hint = current == null ? "—" : current.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (m.dosage.isNotEmpty)
                  Text(
                    m.dosage,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  current == null
                      ? "Currently: not set (28-day estimate)"
                      : "Currently: $current dose${current == 1 ? "" : "s"}",
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: TextField(
              controller: row.controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
            ),
          ),
          IconButton(
            tooltip: "Clear",
            onPressed: enabled ? onCleared : null,
            icon: const Icon(Icons.backspace_outlined),
          ),
        ],
      ),
    );
  }
}
