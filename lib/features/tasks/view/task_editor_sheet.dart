import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:url_launcher/url_launcher.dart";

import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../cubit/tasks_cubit.dart";
import "../models/household_task.dart";

const int _kMaxAttachments = 5;
const int _kMaxFileBytes = 10 * 1024 * 1024;

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({
    super.key,
    required this.careGroupId,
    this.existing,
  });

  final String? careGroupId;
  final CareGroupTask? existing;

  static Future<void> show(
    BuildContext context, {
    required String? careGroupId,
    CareGroupTask? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      showDragHandle: true,
      builder: (ctx) => TaskEditorSheet(
        careGroupId: careGroupId,
        existing: existing,
      ),
    );
  }

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  String? _assigneeUid;
  DateTime? _dueAt;
  final List<PlatformFile> _pending = [];
  bool _saving = false;
  String? _error;
  List<CareGroupMember> _members = [];
  bool _loadingMembers = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    if (t != null) {
      _title.text = t.title;
      _notes.text = t.notes;
      _assigneeUid = t.assignedTo;
      _dueAt = t.dueAt;
    }
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final cg = widget.careGroupId;
    if (cg == null || cg.isEmpty) {
      if (mounted) {
        setState(() {
          _loadingMembers = false;
          _members = [];
        });
      }
      return;
    }
    final repo = context.read<MembersRepository>();
    if (!repo.isAvailable) {
      if (mounted) {
        setState(() {
          _loadingMembers = false;
          _members = [];
        });
      }
      return;
    }
    try {
      final list = await repo.fetchMembers(cg);
      if (mounted) {
        setState(() {
          _members = list;
          _loadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMembers = false;
          _error = e.toString();
        });
      }
    }
  }

  String _fileLabel(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return "File";
    final segs = u.pathSegments;
    if (segs.isEmpty) return "File";
    return segs.last;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _currentAttachmentCount =>
      (widget.existing?.attachmentUrls.length ?? 0) + _pending.length;

  Future<void> _pickFiles() async {
    final take = _kMaxAttachments - _currentAttachmentCount;
    if (take <= 0) {
      return;
    }
    final r = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (r == null) return;
    for (final f in r.files) {
      if (_currentAttachmentCount >= _kMaxAttachments) break;
      if (f.size > _kMaxFileBytes) {
        if (mounted) {
          setState(() => _error = "Each file must be 10 MB or smaller.");
        }
        continue;
      }
      if (f.bytes == null || f.bytes!.isEmpty) {
        if (mounted) {
          setState(() => _error = "Could not read file data.");
        }
        continue;
      }
      setState(() {
        _error = null;
        _pending.add(f);
      });
    }
  }

  void _removePending(int i) {
    setState(() => _pending.removeAt(i));
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = _dueAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: d,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: d.hour, minute: d.minute),
    );
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  static const Duration _kSaveMaxWait = Duration(minutes: 4);

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final cubit = context.read<TasksCubit>();
    final title = _title.text;
    if (title.trim().isEmpty) {
      setState(() {
        _saving = false;
        _error = "Add a task title.";
      });
      return;
    }
    try {
      final work = _isEdit
          ? cubit.updateTask(
              taskId: widget.existing!.id,
              title: title,
              notes: _notes.text,
              dueAt: _dueAt,
              assignedTo: _assigneeUid,
              newAttachments: _pending,
            )
          : cubit.addTask(
              title: title,
              notes: _notes.text,
              dueAt: _dueAt,
              assignedTo: _assigneeUid,
              attachments: _pending,
            );
      await work.timeout(
        _kSaveMaxWait,
        onTimeout: () => throw TimeoutException(
          "Save timed out. Check your network, try smaller files, or try again in a few minutes.",
          _kSaveMaxWait,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    // Clear loading *before* closing so we never get stuck on the spinner.
    setState(() {
      _saving = false;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      top: false,
      left: true,
      right: true,
      bottom: true,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          shrinkWrap: true,
          children: [
          Text(
            _isEdit ? "Edit task" : "New task",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: "Title",
            ),
            textInputAction: TextInputAction.next,
            autofocus: !_isEdit,
          ),
          const SizedBox(height: 12),
          if (widget.careGroupId == null || widget.careGroupId!.isEmpty)
            const Text("Select a care group in your profile to assign tasks to other members.", style: TextStyle(fontSize: 12))
          else if (_loadingMembers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else
            InputDecorator(
              decoration: const InputDecoration(labelText: "Assign to"),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _assigneeUid,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text("Unassigned")),
                    ..._members.map(
                      (m) => DropdownMenuItem<String?>(value: m.userId, child: Text(m.displayName)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _assigneeUid = v),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: "Notes",
              alignLabelWithHint: true,
            ),
            minLines: 2,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Due date & time"),
            subtitle: Text(
              _dueAt == null ? "None set" : _formatDateTime(_dueAt!),
            ),
            trailing: _dueAt == null
                ? TextButton(onPressed: _pickDue, child: const Text("Set"))
                : TextButton(
                    onPressed: () => setState(() => _dueAt = null),
                    child: const Text("Clear"),
                  ),
            onTap: _pickDue,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text("Attachments", style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text("$_currentAttachmentCount / $_kMaxAttachments", style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (widget.existing != null)
            for (final url in widget.existing!.attachmentUrls) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file, size: 20),
                title: Text(
                  _fileLabel(url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () => _openUrl(url),
                  child: const Text("Open"),
                ),
                dense: true,
              ),
            ],
          for (var i = 0; i < _pending.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_circle_outline, size: 20),
              title: Text(
                _pending[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: () => _removePending(i),
                icon: const Icon(Icons.close),
                tooltip: "Remove",
              ),
              dense: true,
            ),
          if (_currentAttachmentCount < _kMaxAttachments)
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickFiles,
              icon: const Icon(Icons.file_upload),
              label: const Text("Add files"),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
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
                : Text(_isEdit ? "Save" : "Create task"),
          ),
        ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")} ${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}";
  }

  Future<void> _openUrl(String url) async {
    final u = Uri.parse(url);
    await launchUrl(u, mode: LaunchMode.platformDefault);
  }
}
