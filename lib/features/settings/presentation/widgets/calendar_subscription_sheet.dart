import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../domain/group_calendar_service.dart";

/// Bottom sheet shown from [CalendarSubscriptionTile]: iCal URL, copy, open in Google Calendar.
Future<void> showGroupCalendarSubscriptionSheet(
  BuildContext context, {
  required GroupCalendarResult config,
  required Future<void> Function(GroupCalendarResult) onOpenGoogle,
}) async {
  final ical = config.icalUrl?.trim() ?? "";

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.paddingOf(ctx).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Group calendar",
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              "Add this to your calendar app to see all scheduled CareShare events.",
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (ical.isNotEmpty) ...[
              const SizedBox(height: 16),
              SelectableText(
                ical,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: ical));
                  if (!ctx.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Link copied")),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text("Copy link"),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Text(
                "No subscription URL has been configured yet. A principal can add a "
                "`groupCalendar` map on this care group in Firestore (`careGroups/{id}`), "
                "or temporarily use the legacy `config/groupCalendar` doc.",
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.error,
                    ),
              ),
            ],
            if (config.calendarId != null && config.calendarId!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await onOpenGoogle(config);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text("Open in Google Calendar"),
                ),
              ),
          ],
        ),
      );
    },
  );
}
