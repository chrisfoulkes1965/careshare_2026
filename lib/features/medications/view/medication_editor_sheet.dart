import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../cubit/medications_cubit.dart";
import "../models/care_group_medication.dart";
import "../rxnorm_medication_suggest_client.dart";

class MedicationEditorSheet extends StatefulWidget {
  const MedicationEditorSheet({super.key, this.existing});

  final CareGroupMedication? existing;

  static Future<void> show(
    BuildContext context, {
    CareGroupMedication? existing,
  }) {
    // Modal routes are not under the same subtree as the page [BlocProvider]; re-provide
    // so [context.read] in the sheet always works.
    final cubit = context.read<MedicationsCubit>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Content applies its own [SafeArea] so the primary button stays above the nav bar
      // (this flag alone is unreliable with scrollable sheet children on Android).
      useSafeArea: false,
      showDragHandle: true,
      builder: (ctx) => BlocProvider<MedicationsCubit>.value(
        value: cubit,
        child: MedicationEditorSheet(existing: existing),
      ),
    );
  }

  @override
  State<MedicationEditorSheet> createState() => _MedicationEditorSheetState();
}

class _MedicationEditorSheetState extends State<MedicationEditorSheet> {
  final _name = TextEditingController();
  final _dosage = TextEditingController();
  final _quantity = TextEditingController();
  final _instructions = TextEditingController();
  final _notes = TextEditingController();
  final _rxNorm = const RxNormMedicationSuggestClient();
  bool _reminderEnabled = false;
  MedicationScheduleType _scheduleType = MedicationScheduleType.daily;
  final Set<int> _selectedWeekdayPlugin = {};
  final List<int> _monthDays = [];
  final List<TimeOfDay> _times = [];
  bool _saving = false;
  String? _error;
  PlatformFile? _newImage;
  bool _clearPhoto = false;
  Timer? _suggestDebounce;
  int _suggestId = 0;
  bool _suggestLoading = false;
  List<String> _nameSuggestions = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    if (m != null) {
      _name.text = m.name;
      _dosage.text = m.dosage;
      _instructions.text = m.instructions;
      _notes.text = m.notes;
      _reminderEnabled = m.reminderEnabled;
      _scheduleType = m.scheduleType;
      _selectedWeekdayPlugin
        ..clear()
        ..addAll(m.scheduleWeekdays);
      _monthDays
        ..clear()
        ..addAll(m.scheduleMonthDays);
      for (final t in m.reminderTimes) {
        _times.add(TimeOfDay(hour: t.hour, minute: t.minute));
      }
      if (m.quantityOnHand != null) {
        _quantity.text = "${m.quantityOnHand}";
      }
    }
    _name.addListener(_onNameTextChanged);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _name.removeListener(_onNameTextChanged);
    _name.dispose();
    _dosage.dispose();
    _quantity.dispose();
    _instructions.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onNameTextChanged() {
    _suggestDebounce?.cancel();
    if (_saving) {
      return;
    }
    final t = _name.text.trim();
    if (t.length < 2) {
      if (_suggestLoading || _nameSuggestions.isNotEmpty) {
        setState(() {
          _suggestLoading = false;
          _nameSuggestions = const [];
        });
      }
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 400), _runNameSuggest);
  }

  Future<void> _runNameSuggest() async {
    final myId = ++_suggestId;
    final q = _name.text.trim();
    if (q.length < 2) {
      if (mounted) {
        setState(() {
          _suggestLoading = false;
          _nameSuggestions = const [];
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _suggestLoading = true);
    }
    try {
      final list = await _rxNorm.suggest(q);
      if (!mounted || myId != _suggestId) {
        return;
      }
      setState(() {
        _suggestLoading = false;
        _nameSuggestions = list;
      });
    } catch (_) {
      if (mounted && myId == _suggestId) {
        setState(() {
          _suggestLoading = false;
          _nameSuggestions = const [];
        });
      }
    }
  }

  void _selectSuggestedName(String name) {
    _name.value = _name.value.copyWith(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    setState(() => _nameSuggestions = const []);
  }

  List<MedicationReminderTime> _toReminderList() {
    return _times
        .map(
          (t) => MedicationReminderTime(
            hour: t.hour,
            minute: t.minute,
          ),
        )
        .toList();
  }

  int get _reminderSlotCount {
    if (!_reminderEnabled || _times.isEmpty) {
      return 0;
    }
    return switch (_scheduleType) {
      MedicationScheduleType.daily => _times.length,
      MedicationScheduleType.weekly => _selectedWeekdayPlugin.length * _times.length,
      MedicationScheduleType.monthly => _monthDays.length * _times.length,
    };
  }

  List<int> _weekdaysToSave() {
    final w = _selectedWeekdayPlugin.toList()..sort();
    return w;
  }

  List<int> _monthDaysToSave() {
    return List<int>.from(_monthDays)..sort();
  }

  Future<void> _addMonthDay() async {
    if (_saving) {
      return;
    }
    var selected = 1;
    final day = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Day of month"),
          content: StatefulBuilder(
            builder: (ctx, setD) {
              return DropdownButton<int>(
                value: selected,
                isExpanded: true,
                items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text("$d"))],
                onChanged: (v) {
                  if (v != null) {
                    setD(() => selected = v);
                  }
                },
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
    if (day == null || !mounted) {
      return;
    }
    if (_monthDays.contains(day)) {
      return;
    }
    setState(() {
      _monthDays.add(day);
      _monthDays.sort();
    });
  }

  Future<void> _addTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _times.isNotEmpty ? _times.last : const TimeOfDay(hour: 8, minute: 0),
    );
    if (t == null) return;
    setState(() {
      _times.add(t);
    });
  }

  void _removeTime(int i) {
    setState(() => _times.removeAt(i));
  }

  Future<void> _pickImage() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    if (f.bytes == null || f.bytes!.isEmpty) {
      setState(() => _error = "Could not read image data.");
      return;
    }
    setState(() {
      _error = null;
      _newImage = f;
      _clearPhoto = false;
    });
  }

  Future<void> _onSave() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = "Add a medication name (e.g. as on your label).");
      return;
    }
    if (_quantity.text.trim().isNotEmpty) {
      final o = int.tryParse(_quantity.text.trim());
      if (o == null) {
        setState(() => _error = "Doses on hand must be a whole number.");
        return;
      }
      if (o < 0) {
        setState(() => _error = "Doses on hand cannot be negative.");
        return;
      }
    }
    if (_reminderEnabled) {
      if (_times.isEmpty) {
        setState(() => _error = "Add at least one reminder time, or turn reminders off.");
        return;
      }
      if (_scheduleType == MedicationScheduleType.weekly && _selectedWeekdayPlugin.isEmpty) {
        setState(() => _error = "Select at least one day of the week, or use Daily/Monthly.");
        return;
      }
      if (_scheduleType == MedicationScheduleType.monthly && _monthDays.isEmpty) {
        setState(() => _error = "Add at least one calendar day of the month, or use Daily/Weekly.");
        return;
      }
      if (_reminderSlotCount > CareGroupMedication.maxNotificationSlots) {
        setState(
          () => _error =
              "Too many reminder times for this device (max ${CareGroupMedication.maxNotificationSlots} scheduled alerts per medicine). Use fewer days or times.",
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final cup = _quantity.text.trim();
    int? qParsed = cup.isEmpty ? null : int.parse(cup);
    final clearQty = _isEdit && cup.isEmpty;
    final cubit = context.read<MedicationsCubit>();
    try {
      if (_isEdit) {
        await cubit.updateMedication(
          medicationId: widget.existing!.id,
          name: _name.text,
          dosage: _dosage.text,
          instructions: _instructions.text,
          notes: _notes.text,
          reminderEnabled: _reminderEnabled,
          reminderTimes: _toReminderList(),
          scheduleType: _scheduleType,
          scheduleWeekdays: _weekdaysToSave(),
          scheduleMonthDays: _monthDaysToSave(),
          quantityOnHand: qParsed,
          clearQuantity: clearQty,
          clearPhoto: _clearPhoto,
          newImage: _newImage,
        );
      } else {
        await cubit.addMedication(
          name: _name.text,
          dosage: _dosage.text,
          instructions: _instructions.text,
          notes: _notes.text,
          reminderEnabled: _reminderEnabled,
          reminderTimes: _toReminderList(),
          scheduleType: _scheduleType,
          scheduleWeekdays: _weekdaysToSave(),
          scheduleMonthDays: _monthDaysToSave(),
          quantityOnHand: qParsed,
          image: _newImage,
        );
      }
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
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
    final m = widget.existing;
    return SafeArea(
      top: false,
      left: true,
      right: true,
      bottom: true,
      // Keeps insets for gesture / 3-button nav when edge-to-edge sets padding to 0.
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          shrinkWrap: true,
          children: [
          Text(
            _isEdit ? "Edit medication" : "Add medication",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (kIsWeb)
            Text(
              "Local reminders to take medicine require the iOS, Android, or desktop app. You can still save prescriptions here on web.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: "Name (as on pack or label)",
              hintText: "Type to search a public name list (RxNorm)",
            ),
            textInputAction: TextInputAction.next,
            autofocus: !_isEdit,
          ),
          if (_suggestLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_nameSuggestions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "U.S. RxNorm (NIH) — for reference; always match your own packaging.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Card(
              margin: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _nameSuggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = _nameSuggestions[i];
                    return ListTile(
                      dense: true,
                      title: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: _saving ? null : () => _selectSuggestedName(s),
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _dosage,
            decoration: const InputDecoration(
              labelText: "Dose (optional)",
              hintText: "e.g. 500mg, 2 tablets",
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Doses on hand (optional)",
              hintText: "Tablets/capsules left; leave empty for 28-day estimate",
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _instructions,
            decoration: const InputDecoration(
              labelText: "How to take (optional)",
              hintText: "e.g. with food, before bed",
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: "Notes (optional)"),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _reminderEnabled,
            onChanged: (v) => setState(() => _reminderEnabled = v),
            title: const Text("Remind me to take this"),
            subtitle: const Text("Local notification on this device; schedule below"),
          ),
          if (_reminderEnabled) ...[
            const Text("Repeat"),
            const SizedBox(height: 4),
            SegmentedButton<MedicationScheduleType>(
              segments: const [
                ButtonSegment(
                  value: MedicationScheduleType.daily,
                  label: Text("Daily"),
                  tooltip: "Every day at the times you add",
                ),
                ButtonSegment(
                  value: MedicationScheduleType.weekly,
                  label: Text("Weekly"),
                  tooltip: "On selected weekdays",
                ),
                ButtonSegment(
                  value: MedicationScheduleType.monthly,
                  label: Text("Monthly"),
                  tooltip: "On certain calendar days each month",
                ),
              ],
              selected: {_scheduleType},
              onSelectionChanged: _saving
                  ? null
                  : (s) {
                      if (s.isEmpty) {
                        return;
                      }
                      setState(() => _scheduleType = s.first);
                    },
            ),
            if (_scheduleType == MedicationScheduleType.weekly) ...[
              const SizedBox(height: 8),
              Text("Days of week (Sun–Sat)", style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var p = 1; p <= 7; p++)
                    FilterChip(
                      label: Text(
                        <String>["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][p - 1],
                      ),
                      selected: _selectedWeekdayPlugin.contains(p),
                      onSelected: _saving
                          ? null
                          : (sel) {
                              setState(() {
                                if (sel) {
                                  _selectedWeekdayPlugin.add(p);
                                } else {
                                  _selectedWeekdayPlugin.remove(p);
                                }
                              });
                            },
                    ),
                ],
              ),
            ],
            if (_scheduleType == MedicationScheduleType.monthly) ...[
              const SizedBox(height: 8),
              Text(
                "Calendar days each month (months without that day are skipped, e.g. 31st in June).",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final d in _monthDays)
                    InputChip(
                      label: Text("$d"),
                      onDeleted: _saving ? null : () => setState(() => _monthDays.remove(d)),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : _addMonthDay,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text("Add day of month"),
                ),
              ),
            ],
            if (_reminderEnabled && _reminderSlotCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                "Scheduled local alerts: $_reminderSlotCount (max ${CareGroupMedication.maxNotificationSlots})",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _reminderSlotCount > CareGroupMedication.maxNotificationSlots
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            Row(
              children: [
                Text("Times", style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _saving ? null : _addTime,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Add time"),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _times.length; i++)
                  InputChip(
                    label: Text(
                      "${_times[i].hour.toString().padLeft(2, "0")}:${_times[i].minute.toString().padLeft(2, "0")}",
                    ),
                    onDeleted: _saving ? null : () => _removeTime(i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (_isEdit && m?.photoUrl != null && m!.photoUrl!.isNotEmpty && !_clearPhoto)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    m.photoUrl!,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                  ),
                ),
                CheckboxListTile(
                  value: _clearPhoto,
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() {
                            _clearPhoto = v ?? false;
                            if (_clearPhoto) {
                              _newImage = null;
                            }
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("Remove photo"),
                ),
              ],
            )
          else if (_newImage != null)
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(_newImage!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                onPressed: _saving ? null : () => setState(() => _newImage = null),
                icon: const Icon(Icons.close),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickImage,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_isEdit ? "Change prescription photo" : "Add prescription photo (optional)"),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _onSave,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? "Save" : "Add medication"),
          ),
        ],
        ),
      ),
    );
  }
}
