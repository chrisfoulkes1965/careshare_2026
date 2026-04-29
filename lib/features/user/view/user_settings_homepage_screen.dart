import "package:flutter/material.dart";

import "package:flutter_bloc/flutter_bloc.dart";

import "package:go_router/go_router.dart";

import "../../profile/profile_cubit.dart";

import "../../profile/profile_state.dart";

import "../models/home_sections_visibility.dart";

import "../repository/user_repository.dart";

class UserSettingsHomepageScreen extends StatelessWidget {
  const UserSettingsHomepageScreen({super.key});

  Future<void> _set(
    BuildContext context,
    HomeSectionsVisibility next,
  ) async {
    try {
      await context.read<ProfileCubit>().setHomeSectionsVisibility(next);
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  bool _visibilityFor(HomeSectionsVisibility v, String id) {
    switch (id) {
      case HomeSectionId.todaysNeeds:
        return v.todaysNeeds;

      case HomeSectionId.calendarEvents:
        return v.calendarEvents;

      case HomeSectionId.tasks:
        return v.tasks;

      case HomeSectionId.medications:
        return v.medications;

      case HomeSectionId.expenses:
        return v.expenses;

      case HomeSectionId.urgentTasks:
        return v.urgentTasks;

      case HomeSectionId.recentActivity:
        return v.recentActivity;

      default:
        return true;
    }
  }

  HomeSectionsVisibility _copyVisibility(
    HomeSectionsVisibility v,
    String id,
    bool on,
  ) {
    switch (id) {
      case HomeSectionId.todaysNeeds:
        return v.copyWith(todaysNeeds: on);

      case HomeSectionId.calendarEvents:
        return v.copyWith(calendarEvents: on);

      case HomeSectionId.tasks:
        return v.copyWith(tasks: on);

      case HomeSectionId.medications:
        return v.copyWith(medications: on);

      case HomeSectionId.expenses:
        return v.copyWith(expenses: on);

      case HomeSectionId.urgentTasks:
        return v.copyWith(urgentTasks: on);

      case HomeSectionId.recentActivity:
        return v.copyWith(recentActivity: on);

      default:
        return v;
    }
  }

  String _subtitle(String id) {
    switch (id) {
      case HomeSectionId.todaysNeeds:
        return "Members marked as receiving care and their short needs";

      case HomeSectionId.calendarEvents:
        return "Team meetings and linked Google Calendar events";

      case HomeSectionId.tasks:
        return "Upcoming tasks that have a due date";

      case HomeSectionId.medications:
        return "Medicine reminder preview";

      case HomeSectionId.expenses:
        return "Recent or upcoming expense entries";

      case HomeSectionId.urgentTasks:
        return "Prioritized open tasks";

      case HomeSectionId.recentActivity:
        return "Notes, journal and task updates";

      default:
        return "";
    }
  }

  String _title(String id) {
    switch (id) {
      case HomeSectionId.todaysNeeds:
        return "Today's needs";

      case HomeSectionId.calendarEvents:
        return "Calendar events";

      case HomeSectionId.tasks:
        return "Tasks";

      case HomeSectionId.medications:
        return "Medications";

      case HomeSectionId.expenses:
        return "Expenses";

      case HomeSectionId.urgentTasks:
        return "Urgent tasks";

      case HomeSectionId.recentActivity:
        return "Recent activity";

      default:
        return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRepo = context.read<UserRepository>();

    if (!userRepo.isAvailable) {
      return Scaffold(
        appBar: AppBar(title: const Text("Homepage")),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Signing in is required to personalize your homepage layout.",
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Homepage sections"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          if (state is! ProfileReady) {
            return const Center(child: CircularProgressIndicator());
          }

          final v = state.profile.resolvedHomeSections;

          final ordered = v.resolvedSectionOrder;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                "Choose what appears on your care group home.",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                "Drag the grip on the left to change vertical order on the "
                "home screen. Turn sections off here if you prefer a calmer "
                "layout—you can reopen features from the toolbar or menu.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: ordered.length,
                onReorder: (oldIndex, newIndex) {
                  var j = newIndex;

                  if (j > oldIndex) {
                    j--;
                  }

                  final next = [...ordered];

                  final item = next.removeAt(oldIndex);

                  next.insert(j, item);

                  _set(context, v.copyWith(sectionOrder: next));
                },
                itemBuilder: (context, index) {
                  final id = ordered[index];

                  final on = _visibilityFor(v, id);

                  return Card(
                    key: ValueKey(id),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(_title(id)),
                      subtitle: Text(_subtitle(id)),
                      trailing: Switch.adaptive(
                        value: on,
                        onChanged: (nextOn) {
                          _set(context, _copyVisibility(v, id, nextOn));
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
