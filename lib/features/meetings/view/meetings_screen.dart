import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/meetings_cubit.dart";
import "../cubit/meetings_state.dart";
import "../models/household_meeting.dart";
import "../repository/meetings_repository.dart";

class MeetingsScreen extends StatelessWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final cg = state.profile.activeCareGroupId;
        if (cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Meetings")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to plan meetings. Complete setup first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey(cg),
          create: (context) => MeetingsCubit(
            repository: context.read<MeetingsRepository>(),
            careGroupId: cg,
          )..subscribe(),
          child: const _MeetingsView(),
        );
      },
    );
  }
}

String _formatDateTime(DateTime d) {
  return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")} "
      "${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}";
}

class _MeetingsView extends StatelessWidget {
  const _MeetingsView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MeetingsCubit, MeetingsState>(
      listener: (context, state) {
        if (state is MeetingsFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        final canCompose = state is MeetingsEmpty || state is MeetingsDisplay;
        return Scaffold(
          appBar: AppBar(
            title: const Text("Meetings"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go("/home");
                }
              },
            ),
          ),
          body: SafeArea(
            child: _MeetingsBody(state: state),
          ),
          floatingActionButton: canCompose
              ? FloatingActionButton(
                  onPressed: () => _showMeetingSheet(context, null),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}

class _MeetingsBody extends StatelessWidget {
  const _MeetingsBody({required this.state});

  final MeetingsState state;

  @override
  Widget build(BuildContext context) {
    if (state is MeetingsInitial || state is MeetingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is MeetingsForbidden) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Multi-party care meetings are not shown in limited “receiving care” mode. "
            "If you are a carer, ask a principal to confirm your care group role.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state is MeetingsEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "No meetings yet. Add scheduled reviews, family discussions, or team check-ins. "
            "Edits: carers and principal carers. Deletion: principal carer only (per your rules).",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state case final MeetingsDisplay display) {
      final items = display.list;
      return BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (p, c) => p.user?.uid != c.user?.uid,
        builder: (context, auth) {
          final selfUid = auth.user?.uid;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final m = items[i];
              final mine = selfUid != null && m.createdBy == selfUid;
              final parts = <String>[];
              if (mine) {
                parts.add("You");
              } else if (m.createdBy.isNotEmpty) {
                parts.add("Organiser");
              }
              if (m.location != null && m.location!.isNotEmpty) {
                parts.add(m.location!);
              }
              if (m.body != null && m.body!.isNotEmpty) {
                final t = m.body!.length > 100 ? "${m.body!.substring(0, 100)}…" : m.body!;
                parts.add(t);
              }
              if (m.meetingAt != null) {
                parts.add(_formatDateTime(m.meetingAt!));
              }
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.groups_2_outlined, color: AppColors.tealPrimary),
                  title: Text(m.title),
                  subtitle: Text(
                    parts.join(" · "),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: parts.length > 2,
                  onTap: () => _showMeetingSheet(context, m),
                ),
              );
            },
          );
        },
      );
    }
    if (state case final MeetingsFailure failure) {
      return Center(child: Text(failure.message));
    }
    return const SizedBox.shrink();
  }
}

Future<void> _showMeetingSheet(
  BuildContext context,
  CareGroupMeeting? existing,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _MeetingFormSheet(
          existing: existing,
        ),
      );
    },
  );
}

class _MeetingFormSheet extends StatefulWidget {
  const _MeetingFormSheet({this.existing});

  final CareGroupMeeting? existing;

  @override
  State<_MeetingFormSheet> createState() => _MeetingFormSheetState();
}

class _MeetingFormSheetState extends State<_MeetingFormSheet> {
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
              "When: ${_formatDateTime(_when)}",
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
