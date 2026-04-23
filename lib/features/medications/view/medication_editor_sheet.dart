import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../cubit/medications_cubit.dart";
import "../models/household_medication.dart";

class MedicationEditorSheet extends StatefulWidget {
  const MedicationEditorSheet({super.key, this.existing});

  final HouseholdMedication? existing;

  static Future<void> show(
    BuildContext context, {
    HouseholdMedication? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => MedicationEditorSheet(existing: existing),
    );
  }

  @override
  State<MedicationEditorSheet> createState() => _MedicationEditorSheetState();
}

class _MedicationEditorSheetState extends State<MedicationEditorSheet> {
  final _name = TextEditingController();
  final _dosage = TextEditingController();
  final _instructions = TextEditingController();
  final _notes = TextEditingController();
  bool _reminderEnabled = false;
  final List<TimeOfDay> _times = [];
  bool _saving = false;
  String? _error;
  PlatformFile? _newImage;
  bool _clearPhoto = false;

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
      for (final t in m.reminderTimes) {
        _times.add(TimeOfDay(hour: t.hour, minute: t.minute));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _instructions.dispose();
    _notes.dispose();
    super.dispose();
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
    if (_reminderEnabled && _times.isEmpty) {
      setState(() => _error = "Add at least one reminder time, or turn reminders off.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final m = widget.existing;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
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
            decoration: const InputDecoration(labelText: "Name (as on pack or label)"),
            textInputAction: TextInputAction.next,
            autofocus: !_isEdit,
          ),
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
            subtitle: const Text("Local notification on this device at the times you add"),
          ),
          if (_reminderEnabled) ...[
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
    );
  }
}
