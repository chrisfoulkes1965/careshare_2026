import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/tasks_cubit.dart";
import "../cubit/tasks_state.dart";
import "../models/household_task.dart";
import "../repository/task_repository.dart";
import "task_editor_sheet.dart";

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final hid = state.profile.activeHouseholdId;
        if (hid == null || hid.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Tasks")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group before tasks can be used. Complete setup or join a care group first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final cg = state.profile.activeCareGroupId;
        return BlocProvider(
          key: ObjectKey(hid),
          create: (context) => TasksCubit(
            repository: context.read<TaskRepository>(),
            householdId: hid,
          )..subscribe(),
          child: _TasksView(careGroupId: cg),
        );
      },
    );
  }
}

class _MemberNameMap extends StatelessWidget {
  const _MemberNameMap({
    required this.careGroupId,
    required this.builder,
  });

  final String? careGroupId;
  final Widget Function(
    BuildContext context,
    Map<String, String> nameByUid,
  ) builder;

  @override
  Widget build(BuildContext context) {
    final cg = careGroupId;
    if (cg == null || cg.isEmpty) {
      return builder(context, {});
    }
    final repo = context.read<MembersRepository>();
    if (!repo.isAvailable) {
      return builder(context, {});
    }
    return StreamBuilder(
      stream: repo.watchMembers(cg),
      builder: (context, snap) {
        final nameBy = <String, String>{};
        for (final m in snap.data ?? const []) {
          nameBy[m.userId] = m.displayName;
        }
        return builder(context, nameBy);
      },
    );
  }
}

class _TasksView extends StatelessWidget {
  const _TasksView({required this.careGroupId});

  final String? careGroupId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tasks"),
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
        child: BlocConsumer<TasksCubit, TasksState>(
          listener: (context, state) {
            if (state is TasksFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is TasksInitial || state is TasksLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is TasksEmpty) {
              return _MemberNameMap(
                careGroupId: careGroupId,
                builder: (context, nameBy) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "No tasks yet. Add one for your care group’s next steps — appointments, medication, or check-ins.",
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  );
                },
              );
            }
            if (state is TasksDisplay) {
              return _MemberNameMap(
                careGroupId: careGroupId,
                builder: (context, nameBy) {
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final t = state.list[i];
                      return _taskCard(context, t, nameBy);
                    },
                  );
                },
              );
            }
            if (state is TasksFailure) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(state.message, textAlign: TextAlign.center),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _taskCard(
    BuildContext context,
    HouseholdTask t,
    Map<String, String> nameBy,
  ) {
    final self = _subtitleLines(t, nameBy);
    return Card(
      child: ListTile(
        onTap: () => _openEditor(context, t),
        title: Text(
          t.title,
          style: TextStyle(
            decoration: t.isDone ? TextDecoration.lineThrough : null,
            color: t.isDone ? AppColors.grey500 : null,
          ),
        ),
        subtitle: self == null
            ? null
            : Text(
                self,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
        isThreeLine: self != null && self.contains("\n"),
        leading: Checkbox(
          value: t.isDone,
          onChanged: (v) async {
            if (v == null) return;
            try {
              await context.read<TasksCubit>().setDone(t.id, v);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            }
          },
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: "Delete task (principal only)",
          onPressed: () async {
            final go = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Delete task?"),
                content: const Text("This can only be completed if you are the principal carer in Firestore rules."),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text("Cancel"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text("Delete"),
                  ),
                ],
              ),
            );
            if (go == true && context.mounted) {
              try {
                await context.read<TasksCubit>().deleteTask(t.id);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            }
          },
        ),
      ),
    );
  }

  String? _subtitleLines(HouseholdTask t, Map<String, String> nameBy) {
    final parts = <String>[];
    if (t.assignedTo != null && t.assignedTo!.isNotEmpty) {
      final n = nameBy[t.assignedTo!];
      if (n != null) {
        parts.add("For $n");
      } else {
        parts.add("Assigned");
      }
    }
    if (t.dueAt != null) {
      parts.add("Due ${_formatDateTime(t.dueAt!)}");
    }
    if (t.attachmentUrls.isNotEmpty) {
      parts.add("${t.attachmentUrls.length} file${t.attachmentUrls.length == 1 ? "" : "s"}");
    }
    if (t.createdAt != null) {
      parts.add("Created ${_formatDate(t.createdAt!)}");
    }
    if (t.notes.isNotEmpty) {
      var line = t.notes.replaceAll("\n", " ");
      if (line.length > 100) {
        line = "${line.substring(0, 100)}…";
      }
      if (parts.isNotEmpty) {
        return "${parts.join(" · ")}\n$line";
      }
      return line;
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(" · ");
  }

  String _formatDateTime(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")} ${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}";
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";
  }

  Future<void> _openEditor(
    BuildContext context,
    HouseholdTask? task,
  ) {
    return TaskEditorSheet.show(
      context,
      careGroupId: careGroupId,
      existing: task,
    );
  }
}
