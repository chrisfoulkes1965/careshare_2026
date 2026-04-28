import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../core/theme/app_colors.dart";
import "../cubit/meetings_cubit.dart";
import "../models/care_group_meeting.dart";

String formatMeetingDateTime(DateTime d) {
  return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")} "
      "${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}";
}

/// Modal is a separate route, so the sheet is wrapped with [MeetingsCubit] from
/// the caller context.
class MeetingEditorSheet extends StatefulWidget {
  const MeetingEditorSheet({super.key, this.existing});

  final CareGroupMeeting? existing;

  static Future<void> show(
    BuildContext context, {
    CareGroupMeeting? existing,
  }) {
    final cubit = context.read<MeetingsCubit>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return BlocProvider<MeetingsCubit>.value(
          value: cubit,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: MeetingEditorSheet(existing: existing),
          ),
        );
      },
    );
  }

  @override
  State<MeetingEditorSheet> createState() => _MeetingEditorSheetState();
}

class _MeetingEditorSheetState extends State<MeetingEditorSheet> {
  late final TextEditingController _titleC;
  late final TextEditingController _bodyC;
  late final TextEditingController _locationC;
  late DateTime _when;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleC = TextEditingController(text: e?.title ?? "");
    _bodyC = TextEditingController(text: e?.body ?? "");
    _locationC = TextEditingController(text: e?.location ?? "");
    _when = e?.meetingAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleC.dispose();
    _bodyC.dispose();
    _locationC.dispose();
    super.dispose();
  }

  Future<void> _pickWhen(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t == null) return;
    setState(() {
      _when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      initialChildSize: 0.85,
      builder: (ctx, scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              isNew ? "New meeting" : "Edit meeting",
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              "When: ${formatMeetingDateTime(_when)}",
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickWhen(ctx),
              icon: const Icon(Icons.event_outlined),
              label: const Text("Date & time"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleC,
              decoration: const InputDecoration(
                labelText: "Title",
                hintText: "e.g. MDT, family call, rota review",
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationC,
              decoration: const InputDecoration(
                labelText: "Location (optional)",
                hintText: "In person, video link, or ward name",
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyC,
              minLines: 3,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: "Agenda & notes",
                alignLabelWithHint: true,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            Text(
              "Only the principal carer can delete a meeting in your security rules.",
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.grey500),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!isNew) ...[
                  TextButton(
                    onPressed: () async {
                      final go = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: const Text("Delete meeting?"),
                          content: const Text(
                            "Only the principal carer can delete. Others will see a permission error.",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(d).pop(false),
                              child: const Text("Cancel"),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(d).pop(true),
                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                      );
                      if (go == true && context.mounted) {
                        final id = widget.existing!.id;
                        try {
                          await context.read<MeetingsCubit>().deleteMeeting(id);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        }
                      }
                    },
                    child: const Text("Delete"),
                  ),
                  const Spacer(),
                ],
                FilledButton(
                  onPressed: () async {
                    if (_titleC.text.trim().isEmpty) return;
                    final cubit = context.read<MeetingsCubit>();
                    try {
                      if (isNew) {
                        await cubit.addMeeting(
                          title: _titleC.text,
                          body: _bodyC.text,
                          location: _locationC.text,
                          meetingAt: _when,
                        );
                      } else {
                        await cubit.updateMeeting(
                          meetingId: widget.existing!.id,
                          title: _titleC.text,
                          body: _bodyC.text,
                          location: _locationC.text,
                          meetingAt: _when,
                        );
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    }
                  },
                  child: Text(isNew ? "Add" : "Save"),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
