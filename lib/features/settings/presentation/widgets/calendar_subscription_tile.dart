import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../profile/profile_cubit.dart";
import "../../../profile/profile_state.dart";
import "../../domain/group_calendar_service.dart";
import "calendar_subscription_sheet.dart";

/// Care group settings entry: subscribe to the shared CareShare Google Calendar.
class CalendarSubscriptionTile extends StatelessWidget {
  const CalendarSubscriptionTile({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final enabled = state is ProfileReady;
        final svc = context.read<GroupCalendarService>();
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text("Subscribe to group calendar"),
          subtitle: const Text(
            "See scheduled tasks in your calendar app (iCal)",
          ),
          enabled: enabled,
          onTap: enabled
              ? () async {
                  final id = state.profile.activeCareGroupId;
                  if (id == null || id.isEmpty) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Could not resolve this care team for calendar settings.",
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    final cfg = await svc.fetchConfigForCareGroup(id);
                    if (!context.mounted) return;
                    await showGroupCalendarSubscriptionSheet(
                      context,
                      config: cfg,
                      onOpenGoogle: svc.launchGoogleCalendar,
                    );
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Could not load calendar settings.",
                        ),
                      ),
                    );
                  }
                }
              : null,
        );
      },
    );
  }
}
