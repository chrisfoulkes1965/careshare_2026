import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../care_group/models/care_group_option.dart";
import "../../../profile/cubit/profile_cubit.dart";

/// Loads and saves **`groupCalendar.{calendarId,icalUrl,timezone}`** on
/// **`careGroups/{dataCareGroupId}`** — the document where shared calendar sync and
/// `linkedCalendarEvents` live (matches [CareGroupOption.dataCareGroupId]).
class CareGroupCalendarSetupSection extends StatefulWidget {
  const CareGroupCalendarSetupSection({super.key, required this.option});

  final CareGroupOption option;

  @override
  State<CareGroupCalendarSetupSection> createState() =>
      _CareGroupCalendarSetupSectionState();
}

class _CareGroupCalendarSetupSectionState
    extends State<CareGroupCalendarSetupSection> {
  final _calendarId = TextEditingController();
  final _icalUrl = TextEditingController();
  final _timezone = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection("careGroups")
          .doc(widget.option.dataCareGroupId)
          .get();
      final gc = snap.data()?["groupCalendar"];
      if (!mounted) {
        return;
      }
      if (gc is Map) {
        final m = gc.map(
          (k, v) => MapEntry(k.toString(), v),
        );
        setState(() {
          _calendarId.text = (m["calendarId"] ?? "").toString().trim();
          _icalUrl.text = (m["icalUrl"] ?? "").toString().trim();
          _timezone.text = (m["timezone"] ?? "").toString().trim();
          _loading = false;
        });
      } else {
        setState(() {
          _calendarId.clear();
          _icalUrl.clear();
          _timezone.clear();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ms = ScaffoldMessenger.of(context);
    try {
      await context.read<ProfileCubit>().mergeCareGroupCalendar(
            careGroupDocId: widget.option.dataCareGroupId,
            calendarId: _calendarId.text,
            icalUrl: _icalUrl.text,
            timezone: _timezone.text,
          );
      if (!mounted) {
        return;
      }
      ms.showSnackBar(
        const SnackBar(content: Text("Calendar settings saved")),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ms.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void didUpdateWidget(CareGroupCalendarSetupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.option.dataCareGroupId != oldWidget.option.dataCareGroupId ||
        widget.option.careGroupId != oldWidget.option.careGroupId) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _calendarId.dispose();
    _icalUrl.dispose();
    _timezone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.option.canEditCareGroupNameThemeAndCalendar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Shared Google Calendar",
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          "Used when tasks have a due date and time — events sync into this calendar. "
          "Share the calendar with your CareShare service account (Make changes to events).",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else ...[
          TextField(
            controller: _calendarId,
            readOnly: !canManage,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Calendar ID",
              hintText:
                  "often …@group.calendar.google.com from Google Calendar settings",
              helperText: canManage
                  ? "Stored on this care group for sync and opening in Google Calendar."
                  : "Only a care group administrator can change these.",
              enabled: !_saving,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _icalUrl,
            readOnly: !canManage,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Calendar subscription URL (optional)",
              hintText:
                  "secret iCal / basic.ics URL for Apple Calendar / Outlook …",
              enabled: !_saving,
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _timezone,
            readOnly: !canManage,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Time zone for due times (optional)",
              hintText:
                  "e.g. Europe/London — leave blank to use global defaults",
              enabled: !_saving,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_loading || _saving) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Save calendar settings"),
            ),
          ],
        ],
      ],
    );
  }
}
