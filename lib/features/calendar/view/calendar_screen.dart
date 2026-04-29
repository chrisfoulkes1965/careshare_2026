import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";
import "package:table_calendar/table_calendar.dart";
import "package:url_launcher/url_launcher.dart";

import "../../../core/theme/app_colors.dart";
import "../../settings/domain/group_calendar_service.dart";
import "../../calendar/models/linked_calendar_event.dart";
import "../../calendar/repository/linked_calendar_events_repository.dart";
import "../../meetings/cubit/meetings_cubit.dart";
import "../../meetings/cubit/meetings_state.dart";
import "../../meetings/models/care_group_meeting.dart";
import "../../meetings/repository/meetings_repository.dart";
import "../../meetings/view/meeting_editor_sheet.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../../tasks/cubit/tasks_cubit.dart";
import "../../tasks/cubit/tasks_state.dart";
import "../../tasks/models/care_group_task.dart";
import "../../tasks/repository/task_repository.dart";
import "../../tasks/view/task_editor_sheet.dart";

/// Calendar cell: either a care meeting or a task (for [TableCalendar] markers).
sealed class _CalGridItem {
  const _CalGridItem();
}

final class _GridMeeting extends _CalGridItem {
  const _GridMeeting(this.m);
  final CareGroupMeeting m;
}

final class _GridTask extends _CalGridItem {
  const _GridTask(this.t);
  final CareGroupTask t;
}

final class _GridLinked extends _CalGridItem {
  const _GridLinked(this.e);
  final LinkedCalendarEvent e;
}

/// Active care group: meetings + tasks with due dates on the month grid.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final cg = state.activeCareGroupDataId;
        if (cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Calendar")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to use the calendar. Complete setup or join a care group first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey("meetings_$cg"),
          create: (context) => MeetingsCubit(
            repository: context.read<MeetingsRepository>(),
            careGroupId: cg,
          )..subscribe(),
          child: BlocProvider(
            key: ObjectKey("tasks_$cg"),
            create: (context) => TasksCubit(
              repository: context.read<TaskRepository>(),
              careGroupId: cg,
            )..subscribe(),
            child: _CalendarBody(careGroupId: cg),
          ),
        );
      },
    );
  }
}

class _CalendarBody extends StatelessWidget {
  const _CalendarBody({required this.careGroupId});

  final String careGroupId;

  @override
  Widget build(BuildContext context) {
    return BlocListener<MeetingsCubit, MeetingsState>(
      listenWhen: (p, c) => c is MeetingsFailure,
      listener: (context, state) {
        if (state is MeetingsFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: BlocListener<TasksCubit, TasksState>(
        listenWhen: (p, c) => c is TasksFailure,
        listener: (context, state) {
          if (state is TasksFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: BlocBuilder<MeetingsCubit, MeetingsState>(
          builder: (context, mState) {
            return BlocBuilder<TasksCubit, TasksState>(
              builder: (context, tState) {
                final linkedRepo =
                    context.read<LinkedCalendarEventsRepository>();
                if (!linkedRepo.isAvailable) {
                  return _CalendarScaffold(
                    mState: mState,
                    tState: tState,
                    linkedEvents: const [],
                    careGroupId: careGroupId,
                  );
                }
                return StreamBuilder<bool>(
                  stream: context
                      .read<GroupCalendarService>()
                      .watchResolvedInboundCalendarForDataDoc(careGroupId),
                  builder: (context, gate) {
                    final mirrorAllowed =
                        !gate.hasError && (gate.data ?? false);
                    return StreamBuilder<List<LinkedCalendarEvent>>(
                      stream: mirrorAllowed
                          ? linkedRepo.watchLinkedEvents(careGroupId)
                          : Stream<List<LinkedCalendarEvent>>.value(
                              const <LinkedCalendarEvent>[],
                            ),
                      builder: (context, linkSnap) {
                        return _CalendarScaffold(
                          mState: mState,
                          tState: tState,
                          linkedEvents: linkSnap.data ?? const [],
                          careGroupId: careGroupId,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CalendarScaffold extends StatelessWidget {
  const _CalendarScaffold({
    required this.mState,
    required this.tState,
    required this.linkedEvents,
    required this.careGroupId,
  });

  final MeetingsState mState;
  final TasksState tState;
  final List<LinkedCalendarEvent> linkedEvents;
  final String careGroupId;

  bool get _canAddMeeting =>
      mState is MeetingsEmpty || mState is MeetingsDisplay;

  bool get _canAddTask => tState is TasksEmpty || tState is TasksDisplay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Calendar"),
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
        actions: [
          TextButton(
            onPressed: () => context.push("/tasks"),
            child: const Text("Tasks"),
          ),
          TextButton(
            onPressed: () => context.push("/meetings"),
            child: const Text("Meetings"),
          ),
        ],
      ),
      body: SafeArea(
        child: _CalendarContent(
          mState: mState,
          tState: tState,
          linkedEvents: linkedEvents,
          careGroupId: careGroupId,
        ),
      ),
      floatingActionButton: _canAddMeeting || _canAddTask
          ? FloatingActionButton(
              onPressed: () => _onFab(
                context,
                careGroupId,
                _canAddMeeting,
                _canAddTask,
              ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _onFab(
    BuildContext context,
    String cg,
    bool canMeeting,
    bool canTask,
  ) {
    if (canMeeting && canTask) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.groups_2_outlined, color: AppColors.tealPrimary),
                title: const Text("New meeting"),
                onTap: () {
                  Navigator.of(ctx).pop();
                  MeetingEditorSheet.show(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.task_alt_outlined, color: AppColors.tealPrimary),
                title: const Text("New task"),
                onTap: () {
                  Navigator.of(ctx).pop();
                  TaskEditorSheet.show(
                    context,
                    careGroupId: cg,
                    existing: null,
                  );
                },
              ),
            ],
          ),
        ),
      );
    } else if (canMeeting) {
      MeetingEditorSheet.show(context);
    } else {
      TaskEditorSheet.show(
        context,
        careGroupId: cg,
        existing: null,
      );
    }
  }
}

Future<void> _openLinkedCalendarEvent(
  BuildContext context,
  LinkedCalendarEvent e,
) async {
  final href = e.htmlLink?.trim();
  if (href != null && href.isNotEmpty) {
    final u = Uri.tryParse(href);
    if (u != null && await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
      return;
    }
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        "Synced events open in Google Calendar once the mirror has run.",
      ),
    ),
  );
}

String _formatTaskDue(DateTime d) {
  return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")} "
      "${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}";
}

class _CalendarContent extends StatefulWidget {
  const _CalendarContent({
    required this.mState,
    required this.tState,
    required this.linkedEvents,
    required this.careGroupId,
  });

  final MeetingsState mState;
  final TasksState tState;
  final List<LinkedCalendarEvent> linkedEvents;
  final String careGroupId;

  @override
  State<_CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends State<_CalendarContent> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _focusedDay = DateTime(n.year, n.month, n.day);
    _selectedDay = _focusedDay;
  }

  List<CareGroupMeeting> _meetings() {
    return switch (widget.mState) {
      MeetingsDisplay d => d.list,
      MeetingsEmpty() => const [],
      MeetingsFailure() => const [],
      MeetingsForbidden() => const [],
      _ => const [],
    };
  }

  List<CareGroupTask> _tasks() {
    return switch (widget.tState) {
      TasksDisplay d => d.list,
      TasksEmpty() => const [],
      TasksFailure() => const [],
      _ => const [],
    };
  }

  List<CareGroupMeeting> _unscheduledMeetings(List<CareGroupMeeting> all) {
    return all.where((m) => m.meetingAt == null).toList();
  }

  List<CareGroupTask> _undatedTasks(List<CareGroupTask> all) {
    return all.where((t) => t.dueAt == null).toList();
  }

  List<CareGroupMeeting> _meetingsOnDay(List<CareGroupMeeting> all, DateTime day) {
    return all
        .where(
          (m) => m.meetingAt != null && isSameDay(m.meetingAt!, day),
        )
        .toList()
      ..sort((a, b) => a.meetingAt!.compareTo(b.meetingAt!));
  }

  List<CareGroupTask> _tasksOnDay(List<CareGroupTask> all, DateTime day) {
    return all
        .where(
          (t) => t.dueAt != null && isSameDay(t.dueAt!, day),
        )
        .toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  }

  List<LinkedCalendarEvent> _linkedOnDay(List<LinkedCalendarEvent> all, DateTime day) {
    return all
        .where((e) => isSameDay(e.startAt, day))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  List<_CalGridItem> _eventsForDay(
    List<CareGroupMeeting> meetings,
    List<CareGroupTask> tasks,
    List<LinkedCalendarEvent> linked,
    DateTime d,
  ) {
    final m = meetings
        .where((x) => x.meetingAt != null && isSameDay(x.meetingAt!, d))
        .map<_CalGridItem>((x) => _GridMeeting(x));
    final t = tasks
        .where((x) => x.dueAt != null && isSameDay(x.dueAt!, d))
        .map<_CalGridItem>((x) => _GridTask(x));
    final k = linked
        .where((x) => isSameDay(x.startAt, d))
        .map<_CalGridItem>((x) => _GridLinked(x));
    return [...m, ...t, ...k].toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mState;
    final t = widget.tState;
    final mWait = m is MeetingsInitial || m is MeetingsLoading;
    final tWait = t is TasksInitial || t is TasksLoading;
    if (mWait || tWait) {
      return const Center(child: CircularProgressIndicator());
    }

    final allMeetings = _meetings();
    final allTasks = _tasks();
    final allLinked = widget.linkedEvents;
    final unscheduledM = _unscheduledMeetings(allMeetings);
    final undatedT = _undatedTasks(allTasks);
    final day = _selectedDay ?? _focusedDay;
    final forM = _meetingsOnDay(allMeetings, day);
    final forT = _tasksOnDay(allTasks, day);
    final forL = _linkedOnDay(allLinked, day);
    final dayEmpty = forM.isEmpty && forT.isEmpty && forL.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (m is MeetingsForbidden) ...[
          Material(
            color: AppColors.amberLight,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "Team meetings are not available in your access mode. Tasks with due dates still show below.",
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          "Meetings & tasks",
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.grey500,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          "Teal dot: meeting · green dot: task due · purple dot: linked Google Calendar. Tap a day for the list.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.grey500,
              ),
        ),
        const SizedBox(height: 12),
        TableCalendar<_CalGridItem>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2035, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (d) =>
              _selectedDay != null && isSameDay(_selectedDay!, d),
          calendarFormat: _calendarFormat,
          eventLoader: (d) => _eventsForDay(allMeetings, allTasks, allLinked, d),
          startingDayOfWeek: StartingDayOfWeek.monday,
          calendarStyle: const CalendarStyle(
            outsideDaysVisible: false,
            todayDecoration: BoxDecoration(
              color: AppColors.tealLight,
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: AppColors.tealDark,
              fontWeight: FontWeight.w600,
            ),
            selectedDecoration: BoxDecoration(
              color: AppColors.tealPrimary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(color: Colors.white),
            markersMaxCount: 3,
            markerSize: 5,
            markersAlignment: Alignment.bottomCenter,
            markerDecoration: BoxDecoration(
              color: AppColors.tealPrimary,
              shape: BoxShape.circle,
            ),
            markersAutoAligned: true,
            canMarkersOverflow: true,
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (ctx, d, ev) {
              if (ev.isEmpty) {
                return const SizedBox.shrink();
              }
              var nMeet = 0;
              var nTask = 0;
              var nLinked = 0;
              for (final e in ev) {
                if (e is _GridMeeting) {
                  nMeet++;
                } else if (e is _GridTask) {
                  nTask++;
                } else if (e is _GridLinked) {
                  nLinked++;
                }
              }
              if (nMeet == 0 && nTask == 0 && nLinked == 0) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (nMeet > 0) ...[
                    for (var i = 0; i < nMeet.clamp(0, 2); i++)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: const BoxDecoration(
                          color: AppColors.tealPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                  if (nTask > 0) ...[
                    for (var i = 0; i < nTask.clamp(0, 2); i++)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: const BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                  if (nLinked > 0) ...[
                    for (var i = 0; i < nLinked.clamp(0, 2); i++)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: const BoxDecoration(
                          color: Color(0xFF8E24AA),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
          headerStyle: HeaderStyle(
            titleCentered: true,
            formatButtonVisible: true,
            titleTextStyle:
                (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(
              color: AppColors.tealDark,
            ),
            leftChevronIcon: const Icon(Icons.chevron_left, color: AppColors.tealPrimary),
            rightChevronIcon: const Icon(Icons.chevron_right, color: AppColors.tealPrimary),
            formatButtonTextStyle: const TextStyle(
              color: AppColors.tealPrimary,
              fontSize: 13,
            ),
            formatButtonDecoration: BoxDecoration(
              border: Border.all(color: AppColors.tealPrimary.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onFormatChanged: (f) {
            if (f != _calendarFormat) {
              setState(() => _calendarFormat = f);
            }
          },
          onPageChanged: (focused) {
            setState(() {
              _focusedDay = focused;
            });
          },
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
          },
        ),
        const SizedBox(height: 16),
        Text(
          isSameDay(day, DateTime.now()) ? "Today" : "Selected day",
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (dayEmpty)
          Text(
            "Nothing on this day.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.grey500,
                ),
          )
        else ...[
          if (forM.isNotEmpty) ...[
            Text(
              "Meetings",
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.grey500,
                  ),
            ),
            const SizedBox(height: 4),
            ...forM.map(
              (m) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(Icons.groups_2_outlined, color: AppColors.tealPrimary),
                  title: Text(m.title),
                  subtitle: m.meetingAt == null
                      ? null
                      : Text(formatMeetingDateTime(m.meetingAt!)),
                  onTap: () => MeetingEditorSheet.show(
                    context,
                    existing: m,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (forT.isNotEmpty) ...[
            Text(
              "Tasks",
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.grey500,
                  ),
            ),
            const SizedBox(height: 4),
            ...forT.map(
              (task) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: Icon(
                    Icons.task_alt_outlined,
                    color: task.isDone ? AppColors.grey500 : AppColors.green,
                  ),
                  title: Text(
                    task.title,
                    style: task.isDone
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: AppColors.grey500,
                          )
                        : null,
                  ),
                  subtitle: task.dueAt == null
                      ? null
                      : Text(_formatTaskDue(task.dueAt!)),
                  onTap: () => TaskEditorSheet.show(
                    context,
                    careGroupId: widget.careGroupId,
                    existing: task,
                  ),
                ),
              ),
            ),
          ],
          if (forL.isNotEmpty) ...[
            Text(
              "Google Calendar",
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.grey500,
                  ),
            ),
            const SizedBox(height: 4),
            ...forL.map(
              (e) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(
                    Icons.calendar_month_outlined,
                    color: Color(0xFF8E24AA),
                  ),
                  title: Text(e.title),
                  subtitle: Text(_formatTaskDue(e.startAt)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openLinkedCalendarEvent(context, e),
                ),
              ),
            ),
          ],
        ],
        if (unscheduledM.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            "Meetings — no date & time",
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            "Not shown on the grid until you set a time.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.grey500,
                ),
          ),
          const SizedBox(height: 8),
          ...unscheduledM.map(
            (m) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const Icon(Icons.event_busy_outlined, color: AppColors.amber),
                title: Text(m.title),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => MeetingEditorSheet.show(
                  context,
                  existing: m,
                ),
              ),
            ),
          ),
        ],
        if (undatedT.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            "Tasks — no due date",
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            "Add a due date to see them on the grid.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.grey500,
                ),
          ),
          const SizedBox(height: 8),
          ...undatedT.map(
            (task) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: Icon(
                  Icons.task_alt_outlined,
                  color: task.isDone ? AppColors.grey500 : AppColors.amber,
                ),
                title: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => TaskEditorSheet.show(
                  context,
                  careGroupId: widget.careGroupId,
                  existing: task,
                ),
              ),
            ),
          ),
        ],
        if (allMeetings.isEmpty && allTasks.isEmpty && allLinked.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "No meetings or tasks yet. Use + to add one, or go to Tasks / Meetings from the app bar.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.grey500,
                  ),
            ),
          ),
      ],
    );
  }
}
