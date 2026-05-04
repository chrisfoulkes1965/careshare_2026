import "dart:async" show Timer, unawaited;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";
import "package:url_launcher/url_launcher.dart";

import "../../../core/care/role_label.dart";
import "../../../core/formatting/currency_format.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/theme/care_group_header_theme.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../journal/models/journal_entry.dart";
import "../../journal/repository/journal_repository.dart";
import "../../notes/models/care_group_note.dart";
import "../../notes/repository/notes_repository.dart";
import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../../setup_wizard/repository/setup_repository.dart";
import "../../settings/repository/group_calendar_service.dart";
import "../../calendar/models/linked_calendar_event.dart";
import "../../calendar/repository/linked_calendar_events_repository.dart";
import "../../expenses/models/care_group_expense.dart";
import "../../expenses/repository/expenses_repository.dart";
import "../../medications/models/care_group_medication.dart";
import "../../medications/repository/medication_care_group_settings_repository.dart";
import "../../medications/repository/medications_repository.dart";
import "home_medication_confirm_banner.dart";
import "home_medication_reorder_banner.dart";
import "../../meetings/models/care_group_meeting.dart";
import "../../meetings/repository/meetings_repository.dart";
import "../../tasks/models/care_group_task.dart";
import "../../tasks/repository/task_repository.dart";
import "../../chat/models/chat_channel.dart";
import "../../chat/repository/chat_repository.dart";
import "../../user/models/home_sections_visibility.dart";
import "../../user/models/user_profile.dart";
import "../../user/view/user_account_menu.dart";
import "../../user/view/widgets/care_group_avatar.dart";
import "../../user/view/widgets/care_user_avatar.dart";

bool _canViewExpenseHistory(CareGroupMember? me) =>
    me != null && me.roles.contains("financial_manager");

String _timeGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) {
    return "Good morning";
  }
  if (h < 17) {
    return "Good afternoon";
  }
  return "Good evening";
}

/// Shown in the home header (top right) in place of the app name.
String _headerCareGroupTitle(ProfileReady pr) {
  final t = pr.activeCareGroupDisplayName?.trim();
  if (t == null || t.isEmpty) {
    return "New Caregroup";
  }
  return t;
}

List<CareGroupMember> _membersForTodayStrip(List<CareGroupMember> all) {
  return all.where((m) => m.roles.contains("receives_care")).take(4).toList();
}

String _shortTag(CareGroupMember m) {
  if (m.roles.contains("receives_care")) {
    return "care";
  }
  if (m.roles.isEmpty) {
    return "member";
  }
  final label = careGroupRoleLabel(m.roles.first);
  if (label.length <= 6) {
    return label;
  }
  return "${label.substring(0, 5)}…";
}

Color _avatarColor(String key) {
  const palette = <Color>[
    Color(0xFFFEE7D6),
    Color(0xFFDEEDF8),
    Color(0xFFE8F5E5),
    Color(0xFFEEEDFE),
    Color(0xFFFDECEA),
  ];
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h + c) * 17;
  }
  return palette[h.abs() % palette.length];
}

Color _onAvatar(Color bg, {Color fallback = AppColors.homeTextPrimary}) {
  if (bg == const Color(0xFFFEE7D6)) {
    return const Color(0xFF8C4A1E);
  }
  if (bg == const Color(0xFFDEEDF8)) {
    return const Color(0xFF185FA5);
  }
  if (bg == const Color(0xFFE8F5E5)) {
    return const Color(0xFF3B6D11);
  }
  if (bg == const Color(0xFFEEEDFE)) {
    return const Color(0xFF534AB7);
  }
  if (bg == const Color(0xFFFDECEA)) {
    return const Color(0xFFA32D2D);
  }
  return fallback;
}

String _formatClock12(DateTime d) {
  var h = d.hour;
  final m = d.minute.toString().padLeft(2, "0");
  final ap = h >= 12 ? "pm" : "am";
  h = h % 12;
  if (h == 0) {
    h = 12;
  }
  return "$h:$m $ap";
}

String _formatTaskDueLine(DateTime? d) {
  if (d == null) {
    return "No due date";
  }
  final now = DateTime.now();
  final t0 = DateTime(now.year, now.month, now.day);
  final td = DateTime(d.year, d.month, d.day);
  if (td == t0) {
    return "Today, ${_formatClock12(d)}";
  }
  final t1 = t0.add(const Duration(days: 1));
  if (td == t1) {
    return "Tomorrow, ${_formatClock12(d)}";
  }
  return "${d.day}/${d.month} · ${_formatClock12(d)}";
}

String _formatRelativeAgo(DateTime? t) {
  if (t == null) {
    return "—";
  }
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) {
    return "now";
  }
  if (diff.inHours < 1) {
    return "${diff.inMinutes}m";
  }
  if (diff.inHours < 24) {
    return "${diff.inHours}h";
  }
  if (diff.inDays < 7) {
    return "${diff.inDays}d";
  }
  return "${(diff.inDays / 7).floor()}w";
}

const int _kHomeActivityFeedLimit = 5;

const int _kChatHomeStripLimit = 8;

final class _ChatHomeRow {
  const _ChatHomeRow({required this.channel, required this.unread});

  final ChatChannel channel;
  final int unread;
}

DateTime _activitySortKey(DateTime? t) =>
    t ?? DateTime.fromMillisecondsSinceEpoch(0);

String _clipActivityTitle(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    return "Untitled";
  }
  if (s.length > 48) {
    return "${s.substring(0, 47)}…";
  }
  return s;
}

/// Journal, notes, and new tasks in one time-ordered list for the home feed.
List<_ActivityRowModel> _buildActivityRowModels(
  BuildContext context, {
  required List<JournalEntry> journal,
  required List<CareGroupNote> notes,
  required List<CareGroupTask> tasks,
  required Map<String, String> nameByUid,
}) {
  String nameFor(String uid) {
    final n = nameByUid[uid]?.trim();
    if (n == null || n.isEmpty) {
      return "Someone";
    }
    return n;
  }

  final lines = <_ActivityRowModel>[];
  for (final e in journal) {
    final raw = e.title.trim().isEmpty ? "Handover" : e.title;
    lines.add(
      _ActivityRowModel(
        sortAt: _activitySortKey(e.createdAt),
        authorUid: e.createdBy,
        authorName: nameFor(e.createdBy),
        kindLabel: "Journal",
        quoted: _clipActivityTitle(raw),
        shownTime: e.createdAt,
        onPressed: () {
          context.push("/journal");
        },
      ),
    );
  }
  for (final n in notes) {
    lines.add(
      _ActivityRowModel(
        sortAt: _activitySortKey(n.createdAt),
        authorUid: n.createdBy,
        authorName: nameFor(n.createdBy),
        kindLabel: "Note",
        quoted: _clipActivityTitle(n.title),
        shownTime: n.createdAt,
        onPressed: () {
          context.push("/notes");
        },
      ),
    );
  }
  for (final t in tasks) {
    final done = t.isDone;
    var q = _clipActivityTitle(t.title);
    if (done) {
      q = "$q (done)";
    }
    lines.add(
      _ActivityRowModel(
        sortAt: _activitySortKey(t.createdAt),
        authorUid: t.createdBy,
        authorName: nameFor(t.createdBy),
        kindLabel: "Task",
        quoted: q,
        shownTime: t.createdAt,
        onPressed: () {
          final u = Uri(
            path: "/tasks",
            queryParameters: {
              "taskId": t.id,
            },
          );
          context.push(u.toString());
        },
      ),
    );
  }
  lines.sort((a, b) => b.sortAt.compareTo(a.sortAt));
  return lines.take(_kHomeActivityFeedLimit).toList();
}

class _ActivityRowModel {
  const _ActivityRowModel({
    required this.sortAt,
    required this.authorUid,
    required this.authorName,
    required this.kindLabel,
    required this.quoted,
    required this.shownTime,
    required this.onPressed,
  });

  final DateTime sortAt;
  final String authorUid;
  final String authorName;
  final String kindLabel;
  final String quoted;
  final DateTime? shownTime;
  final VoidCallback onPressed;
}

const int _kMaxUpcomingScheduleItems = 28;

enum _UpcomingKind { task, meeting, linkedGcal, medication, expense }

final class _UpcomingScheduleItem {
  const _UpcomingScheduleItem._({
    required this.sortAt,
    required this.kind,
    this.task,
    this.meeting,
    this.linked,
    this.medications,
    this.expense,
  });

  factory _UpcomingScheduleItem.task(CareGroupTask t) {
    return _UpcomingScheduleItem._(
      sortAt: t.dueAt!,
      kind: _UpcomingKind.task,
      task: t,
    );
  }

  factory _UpcomingScheduleItem.meeting(CareGroupMeeting m) {
    return _UpcomingScheduleItem._(
      sortAt: m.meetingAt!,
      kind: _UpcomingKind.meeting,
      meeting: m,
    );
  }

  factory _UpcomingScheduleItem.linkedGcal(LinkedCalendarEvent e) {
    return _UpcomingScheduleItem._(
      sortAt: e.startAt,
      kind: _UpcomingKind.linkedGcal,
      linked: e,
    );
  }

  /// One card for several meds with the same reminder [sortAt] (same minute).
  factory _UpcomingScheduleItem.medicationsSameTime(
    List<CareGroupMedication> meds,
    DateTime sortAt,
  ) {
    assert(meds.isNotEmpty);
    return _UpcomingScheduleItem._(
      sortAt: sortAt,
      kind: _UpcomingKind.medication,
      medications: meds,
    );
  }

  factory _UpcomingScheduleItem.expense(CareGroupExpense e) {
    return _UpcomingScheduleItem._(
      sortAt: e.spentAt,
      kind: _UpcomingKind.expense,
      expense: e,
    );
  }

  final DateTime sortAt;
  final _UpcomingKind kind;
  final CareGroupTask? task;
  final CareGroupMeeting? meeting;
  final LinkedCalendarEvent? linked;

  /// Non-null for [kind] == medication; one or more meds scheduled at [sortAt].
  final List<CareGroupMedication>? medications;
  final CareGroupExpense? expense;
}

int _pluginDayFromDartWeekday(int dartWeekday) {
  if (dartWeekday == DateTime.sunday) {
    return 1;
  }
  return dartWeekday + 1;
}

bool _medicationOccursOnDay(CareGroupMedication m, DateTime day) {
  if (!m.reminderEnabled ||
      m.reminderTimes.isEmpty ||
      !m.hasValidReminderSchedule) {
    return false;
  }
  return switch (m.scheduleType) {
    MedicationScheduleType.daily => true,
    MedicationScheduleType.weekly =>
      m.scheduleWeekdays.contains(_pluginDayFromDartWeekday(day.weekday)),
    MedicationScheduleType.monthly => m.scheduleMonthDays.contains(day.day),
  };
}

/// Next reminder moment for sorting (today’s next slot, or next day’s first).
DateTime? _nextMedicationReminderSortTime(CareGroupMedication m) {
  if (!m.reminderEnabled ||
      !m.hasValidReminderSchedule ||
      m.reminderTimes.isEmpty) {
    return null;
  }
  final times = [
    ...m.reminderTimes
  ]..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  for (var add = 0; add < 21; add++) {
    final day = start.add(Duration(days: add));
    if (!_medicationOccursOnDay(m, day)) {
      continue;
    }
    for (final t in times) {
      final cand = DateTime(day.year, day.month, day.day, t.hour, t.minute);
      if (!cand.isBefore(now.subtract(const Duration(seconds: 45)))) {
        return cand;
      }
    }
  }
  return null;
}

({
  List<_UpcomingScheduleItem> calendarItems,
  List<_UpcomingScheduleItem> taskItems,
  List<_UpcomingScheduleItem> medicationItems,
  List<_UpcomingScheduleItem> expenseItems,
}) _buildQuarterUpcomingLanes({
  required List<CareGroupTask> tasks,
  required List<CareGroupMeeting> meetings,
  required List<LinkedCalendarEvent> linkedGcalEvents,
  required List<CareGroupMedication> medications,
  required List<CareGroupExpense> expenses,
}) {
  const maxLane = _kMaxUpcomingScheduleItems;
  final threshold = DateTime.now().subtract(const Duration(seconds: 45));
  final calendarRows = <_UpcomingScheduleItem>[];
  for (final m in meetings) {
    final d = m.meetingAt;
    if (d == null || !d.isAfter(threshold)) {
      continue;
    }
    calendarRows.add(_UpcomingScheduleItem.meeting(m));
  }
  for (final e in linkedGcalEvents) {
    if (!e.startAt.isAfter(threshold)) {
      continue;
    }
    calendarRows.add(_UpcomingScheduleItem.linkedGcal(e));
  }
  calendarRows.sort((a, b) => a.sortAt.compareTo(b.sortAt));
  final calendarItems = calendarRows.take(maxLane).toList();

  final taskRows = <_UpcomingScheduleItem>[];
  for (final t in tasks) {
    final d = t.dueAt;
    if (t.isDone || d == null || !d.isAfter(threshold)) {
      continue;
    }
    taskRows.add(_UpcomingScheduleItem.task(t));
  }
  taskRows.sort((a, b) => a.sortAt.compareTo(b.sortAt));
  final taskItems = taskRows.take(maxLane).toList();

  final medByMinute = <DateTime, List<CareGroupMedication>>{};
  for (final med in medications) {
    final at = _nextMedicationReminderSortTime(med);
    if (at == null) {
      continue;
    }
    final slot = DateTime(at.year, at.month, at.day, at.hour, at.minute);
    medByMinute.putIfAbsent(slot, () => []).add(med);
  }
  final medRows = <_UpcomingScheduleItem>[];
  for (final entry in medByMinute.entries) {
    final medsList = entry.value
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    medRows.add(_UpcomingScheduleItem.medicationsSameTime(medsList, entry.key));
  }
  medRows.sort((a, b) => a.sortAt.compareTo(b.sortAt));
  final medicationItems = medRows.take(maxLane).toList();

  final now = DateTime.now();
  final exCandidates = expenses.where((e) {
    if (e.isRejected) {
      return false;
    }
    final sp = e.spentAt;
    final futureOrToday = sp.isAfter(now.subtract(const Duration(seconds: 30)));
    final last14 = now.subtract(const Duration(days: 14));
    final recentPast = !sp.isBefore(last14) && !sp.isAfter(now);
    return futureOrToday || recentPast;
  }).toList();
  exCandidates.sort((a, b) {
    final af = a.spentAt.isAfter(now.subtract(const Duration(seconds: 30)));
    final bf = b.spentAt.isAfter(now.subtract(const Duration(seconds: 30)));
    if (af != bf) {
      return af ? -1 : 1;
    }
    return a.spentAt.compareTo(b.spentAt);
  });
  final expenseItems = <_UpcomingScheduleItem>[];
  for (final ex in exCandidates.take(7)) {
    expenseItems.add(_UpcomingScheduleItem.expense(ex));
  }
  return (
    calendarItems: calendarItems,
    taskItems: taskItems,
    medicationItems: medicationItems,
    expenseItems: expenseItems,
  );
}

void _onUpcomingScheduleItemTap(
  BuildContext context,
  _UpcomingScheduleItem it,
) {
  if (it.kind == _UpcomingKind.task && it.task != null) {
    final u = Uri(
      path: "/tasks",
      queryParameters: {
        "taskId": it.task!.id,
      },
    );
    context.push(u.toString());
  } else if (it.kind == _UpcomingKind.meeting && it.meeting != null) {
    context.push("/meetings");
  } else if (it.kind == _UpcomingKind.linkedGcal && it.linked != null) {
    unawaited(
      _openLinkedCalendarFromHome(
        context,
        it.linked!,
      ),
    );
  } else if (it.kind == _UpcomingKind.medication &&
      it.medications != null &&
      it.medications!.isNotEmpty) {
    context.push("/medications");
  } else if (it.kind == _UpcomingKind.expense && it.expense != null) {
    context.push("/expenses");
  }
}

Widget _upcomingHorizontalStrip({
  required List<_UpcomingScheduleItem> items,
  required Map<String, String> nameByUid,
  required Map<String, CareGroupMember> membersByUid,
}) {
  return SizedBox(
    height: 118,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final it = items[index];
        return _UpcomingCompactCard(
          item: it,
          nameByUid: nameByUid,
          membersByUid: membersByUid,
          onTap: () => _onUpcomingScheduleItemTap(context, it),
        );
      },
    ),
  );
}

Widget _homeScheduleStripSection({
  required BuildContext context,
  required String title,
  required String emptyHint,
  required String seeAllLabel,
  required VoidCallback onSeeAll,
  required List<_UpcomingScheduleItem> items,
  required Map<String, String> nameByUid,
  required Map<String, CareGroupMember> membersByUid,
  bool loadError = false,
  String loadErrorHint = "Could not load this section.",
}) {
  final s = CareGroupHomeStyleScope.of(context);
  final errStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.error,
      );
  final mutedStyle = TextStyle(
    fontSize: 12,
    color: s.textMuted,
    height: 1.35,
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeader(
        title: title,
        onSeeAll: onSeeAll,
        seeAllLabel: seeAllLabel,
      ),
      const SizedBox(height: 8),
      if (loadError)
        Text(loadErrorHint, style: errStyle)
      else if (items.isEmpty)
        Text(emptyHint, style: mutedStyle)
      else
        _upcomingHorizontalStrip(
          items: items,
          nameByUid: nameByUid,
          membersByUid: membersByUid,
        ),
    ],
  );
}

class _ChatHomeChannelsBody extends StatefulWidget {
  const _ChatHomeChannelsBody({
    super.key,
    required this.dataCareGroupId,
    required this.myUid,
    required this.chatRepository,
    required this.channels,
  });

  final String dataCareGroupId;
  final String myUid;
  final ChatRepository chatRepository;
  final List<ChatChannel> channels;

  @override
  State<_ChatHomeChannelsBody> createState() => _ChatHomeChannelsBodyState();
}

class _ChatHomeChannelsBodyState extends State<_ChatHomeChannelsBody> {
  List<_ChatHomeRow>? _rows;

  List<ChatChannel> get _trimmed =>
      widget.channels.take(_kChatHomeStripLimit).toList();

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _ChatHomeChannelsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameChannelOrder(oldWidget.channels, widget.channels)) {
      unawaited(_reload());
    }
  }

  bool _sameChannelOrder(List<ChatChannel> a, List<ChatChannel> b) {
    final ta = a.take(_kChatHomeStripLimit).map((e) => e.id).toList();
    final tb = b.take(_kChatHomeStripLimit).map((e) => e.id).toList();
    if (ta.length != tb.length) {
      return false;
    }
    for (var i = 0; i < ta.length; i++) {
      if (ta[i] != tb[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _reload() async {
    final top = _trimmed;
    final out = <_ChatHomeRow>[];
    for (final c in top) {
      var unread = 0;
      try {
        final lastRead = await widget.chatRepository.getLastRead(
          widget.dataCareGroupId,
          myUid: widget.myUid,
          channelId: c.id,
        );
        unread = await widget.chatRepository.countUnread(
          widget.dataCareGroupId,
          c.id,
          myUid: widget.myUid,
          lastRead: lastRead,
        );
      } catch (_) {}
      out.add(_ChatHomeRow(channel: c, unread: unread));
    }
    if (!mounted) {
      return;
    }
    setState(() => _rows = out);
  }

  @override
  Widget build(BuildContext context) {
    final top = _trimmed;
    final rows = _rows;
    final loading = rows == null || rows.length != top.length;
    final s = CareGroupHomeStyleScope.of(context);
    if (loading) {
      return SizedBox(
        height: 100,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator.adaptive(
              valueColor: AlwaysStoppedAnimation<Color>(s.textMuted),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final r = rows[index];
          return _ChatHomeChannelCard(
            row: r,
            onTap: () => context.push("/chat/${r.channel.id}"),
          );
        },
      ),
    );
  }
}

class _ChatHomeChannelCard extends StatelessWidget {
  const _ChatHomeChannelCard({
    required this.row,
    required this.onTap,
  });

  final _ChatHomeRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final c = row.channel;
    final subtitle = c.topic.isNotEmpty ? "Topic: ${c.topic}" : "";
    return SizedBox(
      width: 168,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: s.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: s.cardShadow,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.tealPrimary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.forum_outlined, size: 14, color: s.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        "Chat",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: s.textMuted,
                        ),
                      ),
                    ),
                    if (row.unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tealPrimary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          row.unread > 99 ? "99+" : "${row.unread}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    c.name.isEmpty ? "Channel" : c.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: s.textPrimary,
                    ),
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: s.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnsureGeneralChatChannelOnce extends StatefulWidget {
  const _EnsureGeneralChatChannelOnce({
    super.key,
    required this.dataCareGroupId,
    required this.membersCareGroupId,
    required this.chatRepository,
  });

  final String dataCareGroupId;
  final String membersCareGroupId;
  final ChatRepository chatRepository;

  @override
  State<_EnsureGeneralChatChannelOnce> createState() =>
      _EnsureGeneralChatChannelOnceState();
}

class _EnsureGeneralChatChannelOnceState extends State<_EnsureGeneralChatChannelOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        widget.chatRepository.ensureDefaultGeneralChannel(
          dataCareGroupId: widget.dataCareGroupId,
          membersCareGroupId: widget.membersCareGroupId,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _chatHomeSection({
  required BuildContext context,
  required String dataCareGroupId,
  required String membersCareGroupId,
  required String myUid,
  required ChatRepository chatRepository,
}) {
  if (!chatRepository.isAvailable || myUid.isEmpty) {
    return const SizedBox.shrink();
  }
  final s = CareGroupHomeStyleScope.of(context);
  final mutedStyle = TextStyle(
    fontSize: 12,
    color: s.textMuted,
    height: 1.35,
  );
  final errStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.error,
      );
  return StreamBuilder<List<ChatChannel>>(
    stream: chatRepository.watchMyChannels(
      dataCareGroupId,
      myUid: myUid,
    ),
    builder: (context, snap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EnsureGeneralChatChannelOnce(
            key: ValueKey("$dataCareGroupId|$membersCareGroupId"),
            dataCareGroupId: dataCareGroupId,
            membersCareGroupId: membersCareGroupId,
            chatRepository: chatRepository,
          ),
          _SectionHeader(
            title: "Chat",
            onSeeAll: () => context.push("/chat"),
            seeAllLabel: "Chat →",
          ),
          const SizedBox(height: 8),
          if (snap.hasError)
            Text(
              "Could not load channels.",
              style: errStyle,
            )
          else if (!snap.hasData)
            SizedBox(
              height: 72,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation<Color>(s.textMuted),
                  ),
                ),
              ),
            )
          else if ((snap.data ?? const <ChatChannel>[]).isEmpty)
            Text(
              "You're not in any channels yet. Open chat to create one or ask a carer to add you.",
              style: mutedStyle,
            )
          else
            _ChatHomeChannelsBody(
              key: ValueKey(
                snap.data!
                    .take(_kChatHomeStripLimit)
                    .map((e) => e.id)
                    .join("|"),
              ),
              dataCareGroupId: dataCareGroupId,
              myUid: myUid,
              chatRepository: chatRepository,
              channels: snap.data!,
            ),
        ],
      );
    },
  );
}

List<Widget> _homeOrderedLandingSectionWidgets({
  required BuildContext context,
  required HomeSectionsVisibility sections,
  required String memberListCareGroupId,
  required String dataCareGroupId,
  required String currentUserUid,
  required MembersRepository membersRepository,
  required TaskRepository taskRepository,
  required ChatRepository chatRepository,
  required JournalRepository journalRepository,
  required NotesRepository notesRepository,
  required Map<String, String> nameByUid,
  required Map<String, CareGroupMember> membersByUid,
  required ({
    List<_UpcomingScheduleItem> calendarItems,
    List<_UpcomingScheduleItem> taskItems,
    List<_UpcomingScheduleItem> medicationItems,
    List<_UpcomingScheduleItem> expenseItems,
  }) lanes,
  required bool calendarErr,
  required bool tasksErr,
  required bool medicationsErr,
  required bool expensesErr,
}) {
  final out = <Widget>[];
  for (final id in sections.resolvedSectionOrder) {
    if (!sections.isSectionVisible(id)) {
      continue;
    }
    final gap = out.isEmpty
        ? null
        : (id == HomeSectionId.recentActivity
            ? const SizedBox(height: 12)
            : const SizedBox(height: 8));
    if (gap != null) {
      out.add(gap);
    }

    switch (id) {
      case HomeSectionId.todaysNeeds:
        out.add(
          _TodayNeedsSection(
            careGroupId: memberListCareGroupId,
            dataCareGroupId: dataCareGroupId,
            membersRepository: membersRepository,
          ),
        );
        break;
      case HomeSectionId.calendarEvents:
        out.add(
          _homeScheduleStripSection(
            context: context,
            title: "Calendar events",
            emptyHint:
                "No upcoming meetings or linked calendar events — connect your calendar from care group settings.",
            seeAllLabel: "Calendar →",
            onSeeAll: () => context.push("/calendar"),
            items: lanes.calendarItems,
            nameByUid: nameByUid,
            membersByUid: membersByUid,
            loadError: calendarErr,
          ),
        );
        break;
      case HomeSectionId.tasks:
        out.add(
          _homeScheduleStripSection(
            context: context,
            title: "Tasks",
            emptyHint: "No upcoming tasks with a due date.",
            seeAllLabel: "Tasks →",
            onSeeAll: () => context.push("/tasks"),
            items: lanes.taskItems,
            nameByUid: nameByUid,
            membersByUid: membersByUid,
            loadError: tasksErr,
          ),
        );
        break;
      case HomeSectionId.chat:
        out.add(
          _chatHomeSection(
            context: context,
            dataCareGroupId: dataCareGroupId,
            membersCareGroupId: memberListCareGroupId,
            myUid: currentUserUid,
            chatRepository: chatRepository,
          ),
        );
        break;
      case HomeSectionId.medications:
        out.add(
          _homeScheduleStripSection(
            context: context,
            title: "Medications",
            emptyHint: "No medicine reminders scheduled ahead.",
            seeAllLabel: "Medicines →",
            onSeeAll: () => context.push("/medications"),
            items: lanes.medicationItems,
            nameByUid: nameByUid,
            membersByUid: membersByUid,
            loadError: medicationsErr,
          ),
        );
        break;
      case HomeSectionId.expenses:
        out.add(
          _homeScheduleStripSection(
            context: context,
            title: "Expenses",
            emptyHint:
                "No recent or upcoming expenses in the last couple of weeks.",
            seeAllLabel: "Expenses →",
            onSeeAll: () => context.push("/expenses"),
            items: lanes.expenseItems,
            nameByUid: nameByUid,
            membersByUid: membersByUid,
            loadError: expensesErr,
          ),
        );
        break;
      case HomeSectionId.urgentTasks:
        out.add(
          _UrgentTasksSection(
            memberListCareGroupId: memberListCareGroupId,
            dataCareGroupId: dataCareGroupId,
            membersRepository: membersRepository,
            taskRepository: taskRepository,
          ),
        );
        break;
      case HomeSectionId.recentActivity:
        out.add(
          _RecentActivitySection(
            memberListCareGroupId: memberListCareGroupId,
            dataCareGroupId: dataCareGroupId,
            membersRepository: membersRepository,
            journalRepository: journalRepository,
            notesRepository: notesRepository,
            taskRepository: taskRepository,
          ),
        );
        break;
      default:
        break;
    }
  }
  return out;
}

Future<void> _openLinkedCalendarFromHome(
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
  await context.push("/calendar");
}

List<CareGroupTask> _urgentOpenTasksFirst(List<CareGroupTask> all) {
  final open = all.where((t) => !t.isDone).toList();
  int rank(CareGroupTask t) {
    final n = DateTime.now();
    final d = t.dueAt;
    if (d != null && d.isBefore(n)) {
      return 0;
    }
    if (d != null && d.difference(n) <= const Duration(hours: 24)) {
      return 1;
    }
    final un = t.assignedTo == null || t.assignedTo!.isEmpty;
    if (un) {
      return 2;
    }
    return 3;
  }

  open.sort((a, b) {
    final c = rank(a).compareTo(rank(b));
    if (c != 0) {
      return c;
    }
    final da = a.dueAt;
    final db = b.dueAt;
    if (da == null && db == null) {
      return 0;
    }
    if (da == null) {
      return 1;
    }
    if (db == null) {
      return -1;
    }
    return da.compareTo(db);
  });
  return open.take(4).toList();
}

Color _urgencyBarColor(
  CareGroupTask t, {
  required Color onTrackColor,
}) {
  if (t.assignedTo == null || t.assignedTo!.isEmpty) {
    return const Color(0xFFC0B0A0);
  }
  final d = t.dueAt;
  if (d == null) {
    return const Color(0xFF1A7F7A);
  }
  if (d.isBefore(DateTime.now())) {
    return const Color(0xFFE24B4A);
  }
  if (d.difference(DateTime.now()) <= const Duration(hours: 24)) {
    return const Color(0xFFEF9F27);
  }
  return onTrackColor;
}

String _nameForUid(String? uid, Map<String, String> byUid) {
  if (uid == null || uid.isEmpty) {
    return "Unassigned";
  }
  return byUid[uid]?.trim() ?? "Member";
}

UserProfile _userProfileFromCareGroupMember(CareGroupMember m) {
  return UserProfile(
    uid: m.userId,
    email: "",
    displayName: m.displayName,
    photoUrl: m.photoUrl,
    avatarIndex: m.avatarIndex,
  );
}

String _initialsForName(String name) {
  final parts = name.trim().split(RegExp(r"\s+")).where((e) => e.isNotEmpty);
  if (parts.isEmpty) {
    return "?";
  }
  if (parts.length == 1) {
    return parts.first.length >= 2
        ? parts.first.substring(0, 2).toUpperCase()
        : parts.first.toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Runs overdue dose stock adjustments while the home tab is open (no need to open Meds).
class _SyncScheduledMedicationInventory extends StatefulWidget {
  const _SyncScheduledMedicationInventory({
    required this.careGroupDataId,
    required this.medicationsRepository,
    required this.child,
  });

  final String careGroupDataId;
  final MedicationsRepository medicationsRepository;
  final Widget child;

  @override
  State<_SyncScheduledMedicationInventory> createState() =>
      _SyncScheduledMedicationInventoryState();
}

class _SyncScheduledMedicationInventoryState extends State<_SyncScheduledMedicationInventory> {
  Timer? _timer;

  void _kick() {
    if (!widget.medicationsRepository.isAvailable) {
      return;
    }
    unawaited(
      widget.medicationsRepository.applyScheduledDoseInventoryForOverdueAcks(widget.careGroupDataId),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _kick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Care group “landing” layout inspired by the warm homepage mockup.
class HomeLandingView extends StatelessWidget {
  const HomeLandingView({
    super.key,
    required this.pr,
    required this.authSnapshot,
    required this.email,
    required this.showWizardBanner,
  });

  final ProfileReady pr;

  /// Auth session identity (`AuthBloc` / Firebase getters mapped to [UserProfile]).
  final UserProfile? authSnapshot;
  final String email;
  final bool showWizardBanner;

  @override
  Widget build(BuildContext context) {
    final profile = pr.profile;
    final groupName = _headerCareGroupTitle(pr);
    final name = profile.displayName.trim().isNotEmpty
        ? profile.displayName
        : (email.split("@").first);
    final memberDocId = pr.activeCareGroupMemberDocId;
    final dataId = pr.activeCareGroupDataId;
    final headerStyle = resolveCareGroupHeaderStyle(
      activeThemeArgb: pr.activeCareGroupThemeArgb,
    );
    final homeStyle = resolveCareGroupHomePageStyle(
      activeThemeArgb: pr.activeCareGroupThemeArgb,
    );
    final darkHeader = headerStyle.background.computeLuminance() < 0.5;

    Widget homeConfigurableLanding() {
      return _HomeConfigurableLandingSections(
        homeSections: profile.resolvedHomeSections.intersectGroupHomepagePolicy(
          pr.activeCareGroupOption?.homepageSectionsPolicy,
        ),
        memberListCareGroupId: memberDocId,
        dataCareGroupId: dataId,
        currentUserUid: profile.uid,
        membersRepository: context.read<MembersRepository>(),
        taskRepository: context.read<TaskRepository>(),
        meetingsRepository: context.read<MeetingsRepository>(),
        linkedCalendarEventsRepository: context.read<LinkedCalendarEventsRepository>(),
        medicationsRepository: context.read<MedicationsRepository>(),
        expensesRepository: context.read<ExpensesRepository>(),
        journalRepository: context.read<JournalRepository>(),
        notesRepository: context.read<NotesRepository>(),
        chatRepository: context.read<ChatRepository>(),
      );
    }

    return CareGroupHomeStyleScope(
      style: homeStyle,
      activeThemeArgb: pr.activeCareGroupThemeArgb,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              darkHeader ? Brightness.light : Brightness.dark,
          statusBarBrightness: darkHeader ? Brightness.dark : Brightness.light,
        ),
        child: ColoredBox(
          color: homeStyle.scaffoldBackground,
          child: RefreshIndicator(
            onRefresh: () => context.read<ProfileCubit>().refresh(),
            color: homeStyle.refreshIndicator,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _Header(
                  pr: pr,
                  authSnapshot: authSnapshot,
                  email: email,
                  groupName: groupName,
                  name: name,
                  headerStyle: headerStyle,
                  onOpenTool: (path) => context.push(path),
                ),
                const SizedBox(height: 8),
                if (profile.needsWizard) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _StartSetupBanner(
                      onStart: () => context.go("/setup"),
                    ),
                  ),
                ],
                if (showWizardBanner) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _WizardBanner(
                      onContinue: () async {
                        final uid = context.read<AuthBloc>().state.user?.uid;
                        if (uid == null) {
                          return;
                        }
                        final repo = context.read<SetupRepository>();
                        if (repo.isAvailable) {
                          await repo.resumeWizard(uid);
                          if (!context.mounted) {
                            return;
                          }
                          await context.read<ProfileCubit>().refresh();
                        }
                        if (!context.mounted) {
                          return;
                        }
                        context.go("/setup");
                      },
                    ),
                  ),
                ],
                if (pr.careGroupOptions.length > 1) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            context.push("/select-care-group?picker=1"),
                        icon: const Icon(Icons.swap_horiz_outlined, size: 20),
                        label: const Text("Switch care group"),
                        style: TextButton.styleFrom(
                          foregroundColor: CareGroupHomeStyleScope.of(context)
                              .switchCareGroupText,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                if (dataId != null &&
                    dataId.isNotEmpty &&
                    profile
                        .resolvedAlertPreferences.medicationReorder.inApp) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                    child: HomeMedicationReorderBanner(
                      careGroupDataId: dataId,
                      medicationsRepository:
                          context.read<MedicationsRepository>(),
                      settingsRepository:
                          context.read<MedicationCareGroupSettingsRepository>(),
                    ),
                  ),
                ],
                if (dataId != null &&
                    dataId.isNotEmpty &&
                    profile.resolvedAlertPreferences.medicationDue.inApp) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                    child: HomeMedicationConfirmBanner(
                      careGroupDataId: dataId,
                      medicationsRepository:
                          context.read<MedicationsRepository>(),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  child: dataId != null && dataId.isNotEmpty
                      ? _SyncScheduledMedicationInventory(
                          careGroupDataId: dataId,
                          medicationsRepository: context.read<MedicationsRepository>(),
                          child: homeConfigurableLanding(),
                        )
                      : homeConfigurableLanding(),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _AddCta(
                    onPressed: () => _openAddMenu(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _openAddMenu(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      void go(String route) {
        Navigator.of(ctx).pop();
        context.push(route);
      }

      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                "What would you like to add?",
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: const Text("Task"),
              subtitle: const Text("Shared to-do for your care group"),
              onTap: () => go("/tasks"),
            ),
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text("Note"),
              subtitle: const Text("Care notes and updates"),
              onTap: () => go("/notes"),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text("Document"),
              subtitle: const Text("Upload to the document library"),
              onTap: () => go("/document-library"),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text("Photo"),
              subtitle: const Text("Add to the shared photo gallery"),
              onTap: () => go("/photo-gallery"),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text("Expense"),
              subtitle: const Text("Log spending for reimbursement"),
              onTap: () => go("/expenses"),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text("Journal entry"),
              subtitle: const Text("Day-to-day care journal"),
              onTap: () => go("/journal"),
            ),
            ListTile(
              leading: const Icon(Icons.medication_outlined),
              title: const Text("Medication"),
              subtitle: const Text("Prescriptions and reminders"),
              onTap: () => go("/medications"),
            ),
          ],
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.pr,
    required this.authSnapshot,
    required this.email,
    required this.groupName,
    required this.name,
    required this.headerStyle,
    required this.onOpenTool,
  });

  final ProfileReady pr;
  final UserProfile? authSnapshot;
  final String email;
  final String groupName;
  final String name;
  final CareGroupHeaderStyle headerStyle;
  final void Function(String path) onOpenTool;

  @override
  Widget build(BuildContext context) {
    const headerActionSize = 40.0;
    const headerIconSize = 26.0;
    final top = MediaQuery.viewPaddingOf(context).top;
    final h = headerStyle;
    final s = CareGroupHomeStyleScope.of(context);
    final menuToolbarChips = _toolbarChipsForCareTeamMenu(s.toolBarChips);
    final actionStyle = IconButton.styleFrom(
      minimumSize: const Size(headerActionSize, headerActionSize),
      fixedSize: const Size(headerActionSize, headerActionSize),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, top + 10, 12, 18),
      decoration: BoxDecoration(
        color: h.background,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                AppAssets.logoMark,
                height: headerActionSize,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                color: h.logoTint,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.spa_outlined, size: 36, color: h.logoTint);
                },
              ),
              const SizedBox(width: 10),
              CareGroupAvatar(
                radius: headerActionSize / 2,
                photoUrl: pr.activeCareGroupOption?.photoUrl,
                fallbackName: groupName,
                backgroundColor: h.avatarMaterialColor,
                foregroundColor: h.onBackground,
                photoBackgroundColor: h.avatarRingColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (context.mounted) {
                            context.push("/user-settings/care-group");
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Tooltip(
                            message: "Care group settings",
                            child: Row(
                              children: [
                                Icon(
                                  Icons.group_outlined,
                                  size: 22,
                                  color: h.onBackground,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    groupName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      color: h.onBackground,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${_timeGreeting()}, $name",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: h.onBackgroundMuted,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: h.onBackgroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: "Refresh",
                    onPressed: () => context.read<ProfileCubit>().refresh(),
                    style: actionStyle,
                    icon: Icon(
                      Icons.refresh,
                      size: headerIconSize,
                      color: h.onBackground,
                    ),
                  ),
                  IconButton(
                    tooltip: "Care group settings",
                    onPressed: () {
                      if (context.mounted) {
                        context.push("/user-settings/care-group");
                      }
                    },
                    style: actionStyle,
                    icon: Icon(
                      Icons.settings_outlined,
                      size: headerIconSize,
                      color: h.onBackground,
                    ),
                  ),
                  MenuAnchor(
                    style: MenuStyle(
                      backgroundColor: WidgetStatePropertyAll(
                        s.scaffoldBackground,
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                    builder: (context, controller, child) {
                      return IconButton(
                        tooltip: "Care team tools",
                        onPressed: () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                        style: actionStyle,
                        icon: Icon(
                          Icons.grid_view_rounded,
                          size: headerIconSize,
                          color: h.onBackground,
                        ),
                      );
                    },
                    menuChildren: [
                      for (var i = 0; i < _kCareTeamTools.length; i++)
                        MenuItemButton(
                          onPressed: () {
                            onOpenTool(_kCareTeamTools[i].$3);
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 200),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: menuToolbarChips[i].background,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                    _kCareTeamTools[i].$1,
                                    size: 18,
                                    color: menuToolbarChips[i].iconColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(_kCareTeamTools[i].$2),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (authSnapshot != null)
                    SizedBox(
                      width: headerActionSize,
                      height: headerActionSize,
                      child: Center(
                        child: Material(
                          color:
                              h.avatarMaterialColor ?? const Color(0xFF6B4D35),
                          shape: CircleBorder(
                            side: BorderSide(
                              color:
                                  h.avatarRingColor ?? const Color(0xFF8C6E55),
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              showUserAccountMenu(
                                context,
                                signedInIdentity: authSnapshot!,
                                profileState: pr,
                              );
                            },
                            customBorder: const CircleBorder(),
                            child: CareUserAvatar(
                              radius: 20,
                              authFallback: authSnapshot!,
                              profile: pr.profile,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      width: headerActionSize,
                      height: headerActionSize,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _kCareTeamTools = <(IconData, String, String)>[
  (Icons.task_alt_outlined, "Tasks", "/tasks"),
  (Icons.calendar_month_outlined, "Calendar", "/calendar"),
  (Icons.medication_outlined, "Meds", "/medications"),
  (Icons.route_outlined, "Pathways", "/pathways"),
  (Icons.mail_outline, "Invites", "/invitations"),
  (Icons.note_alt_outlined, "Notes", "/notes"),
  (Icons.photo_library_outlined, "Photos", "/photo-gallery"),
  (Icons.menu_book_outlined, "Journal", "/journal"),
  (Icons.contact_phone_outlined, "Contacts", "/contacts"),
  (Icons.payments_outlined, "Expenses", "/expenses"),
  (Icons.groups_2_outlined, "Meetings", "/meetings"),
  (Icons.folder_open_outlined, "Documents", "/document-library"),
  (Icons.forum_outlined, "Chat", "/chat"),
];

/// [CareGroupHomePageStyle.toolBarChips] must cover every [_kCareTeamTools] row;
/// Always returns exactly [_kCareTeamTools.length] entries so “Care team tools”
/// menu indexing can never run past the chip list (e.g. after cold start / notification).
List<({Color background, Color iconColor})> _toolbarChipsForCareTeamMenu(
  List<({Color background, Color iconColor})> chips,
) {
  final need = _kCareTeamTools.length;
  final fallback = (
    background: AppColors.tealLight,
    iconColor: AppColors.tealPrimary,
  );
  final pad = chips.isEmpty ? fallback : chips.last;
  final out = List<({Color background, Color iconColor})>.from(chips);
  while (out.length < need) {
    out.add(pad);
  }
  if (out.length > need) {
    out.removeRange(need, out.length);
  }
  return out;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll, this.seeAllLabel});

  final String title;
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: s.textPrimary,
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(seeAllLabel ?? "See all →"),
          ),
      ],
    );
  }
}

/// Empty “today’s needs” when the group has members but none with [receives_care].
Widget _receivingCareMembersLinkHint(BuildContext context) {
  final s = CareGroupHomeStyleScope.of(context);
  final base = TextStyle(
    fontSize: 12,
    color: s.textMuted,
    height: 1.4,
  );
  final linkStyle = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: s.textPrimary,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationColor: s.textPrimary,
  );
  return Text.rich(
    TextSpan(
      style: base,
      children: [
        const TextSpan(
          text:
              "No one in this care group is marked as receiving care yet. Add or update roles in ",
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                if (context.mounted) {
                  context.push("/members");
                }
              },
              child: Text("Members", style: linkStyle),
            ),
          ),
        ),
        const TextSpan(text: "."),
      ],
    ),
  );
}

class _TodayNeedsSection extends StatelessWidget {
  const _TodayNeedsSection({
    required this.careGroupId,
    required this.dataCareGroupId,
    required this.membersRepository,
  });

  final String? careGroupId;
  final String? dataCareGroupId;
  final MembersRepository membersRepository;

  @override
  Widget build(BuildContext context) {
    if (careGroupId == null ||
        careGroupId!.isEmpty ||
        !membersRepository.isAvailable) {
      final s = CareGroupHomeStyleScope.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: "Today's needs"),
          const SizedBox(height: 8),
          _EmptyTodayCard(
            child: Text(
              "No care team loaded yet. Pull to refresh or open care team settings.",
              style: TextStyle(
                fontSize: 12,
                color: s.textMuted,
                height: 1.4,
              ),
            ),
          ),
        ],
      );
    }
    return StreamBuilder<List<CareGroupMember>>(
      stream: membersRepository.watchMembersOrRoster(
        careGroupId!,
        dataCareGroupId,
      ),
      builder: (context, snap) {
        final all = snap.data ?? const [];
        final members = _membersForTodayStrip(all);
        if (members.length == 1) {
          return const SizedBox.shrink();
        }
        final s = CareGroupHomeStyleScope.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: "Today's needs",
              onSeeAll: () => context.push("/members"),
              seeAllLabel: "See all →",
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: s.todayStripBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: s.todayStripBorder),
              ),
              child: members.isEmpty
                  ? _EmptyTodayCard(
                      child: all.isEmpty
                          ? Text(
                              "When your care team has members, you can see at a glance who needs support.",
                              style: TextStyle(
                                fontSize: 12,
                                color: s.textMuted,
                                height: 1.4,
                              ),
                            )
                          : _receivingCareMembersLinkHint(context),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Who needs help today",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: s.todayNeedsAccent,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final m in members)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: _PersonChip(
                                    member: m,
                                    onTap: () => context.push("/members"),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyTodayCard extends StatelessWidget {
  const _EmptyTodayCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: s.todayStripBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.todayStripBorder),
      ),
      child: child,
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.member, required this.onTap});
  final CareGroupMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final initials = member.displayName.isNotEmpty
        ? member.displayName
            .trim()
            .split(RegExp(r"\s+"))
            .where((e) => e.isNotEmpty)
            .map((e) => e[0].toUpperCase())
            .take(2)
            .join()
        : "?";
    final bg = _avatarColor(member.userId);
    final fg = _onAvatar(bg, fallback: s.textPrimary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 64,
            child: Text(
              member.displayName.split(" ").first,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: s.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: s.chipTagBackground,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _shortTag(member),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: s.chipTagForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeConfigurableLandingSections extends StatelessWidget {
  const _HomeConfigurableLandingSections({
    required this.homeSections,
    required this.memberListCareGroupId,
    required this.dataCareGroupId,
    required this.currentUserUid,
    required this.membersRepository,
    required this.taskRepository,
    required this.meetingsRepository,
    required this.linkedCalendarEventsRepository,
    required this.medicationsRepository,
    required this.expensesRepository,
    required this.journalRepository,
    required this.notesRepository,
    required this.chatRepository,
  });

  final HomeSectionsVisibility homeSections;
  final String? memberListCareGroupId;
  final String? dataCareGroupId;
  final String currentUserUid;
  final MembersRepository membersRepository;
  final TaskRepository taskRepository;
  final MeetingsRepository meetingsRepository;
  final LinkedCalendarEventsRepository linkedCalendarEventsRepository;
  final MedicationsRepository medicationsRepository;
  final ExpensesRepository expensesRepository;
  final JournalRepository journalRepository;
  final NotesRepository notesRepository;
  final ChatRepository chatRepository;

  @override
  Widget build(BuildContext context) {
    if (memberListCareGroupId == null ||
        memberListCareGroupId!.isEmpty ||
        dataCareGroupId == null ||
        dataCareGroupId!.isEmpty ||
        !membersRepository.isAvailable) {
      return const SizedBox.shrink();
    }
    if (!taskRepository.isAvailable &&
        !meetingsRepository.isAvailable &&
        !linkedCalendarEventsRepository.isAvailable &&
        !medicationsRepository.isAvailable &&
        !expensesRepository.isAvailable &&
        !chatRepository.isAvailable) {
      return const SizedBox.shrink();
    }
    final membersCg = memberListCareGroupId!;
    final dataCg = dataCareGroupId!;
    return StreamBuilder<List<CareGroupMember>>(
      stream:
          membersRepository.watchMembersOrRoster(membersCg, dataCareGroupId),
      builder: (context, memSnap) {
        final members = memSnap.data ?? const <CareGroupMember>[];
        final byUid = {
          for (final m in members) m.userId: m.displayName,
        };
        final membersByUid = {for (final m in members) m.userId: m};
        return StreamBuilder<List<CareGroupTask>>(
          stream: taskRepository.isAvailable
              ? taskRepository.watchTasks(dataCg)
              : Stream<List<CareGroupTask>>.value(const <CareGroupTask>[]),
          builder: (context, taskSnap) {
            return StreamBuilder<List<CareGroupMeeting>>(
              stream: meetingsRepository.isAvailable
                  ? meetingsRepository.watchMeetings(dataCg)
                  : Stream<List<CareGroupMeeting>>.value(
                      const <CareGroupMeeting>[]),
              builder: (context, meetSnap) {
                return StreamBuilder<bool>(
                  stream: context
                      .read<GroupCalendarService>()
                      .watchResolvedInboundCalendarForDataDoc(dataCg),
                  builder: (context, resolvedGate) {
                    final mirrorAllowed =
                        !resolvedGate.hasError && (resolvedGate.data ?? false);
                    return StreamBuilder<List<LinkedCalendarEvent>>(
                      stream: linkedCalendarEventsRepository.isAvailable &&
                              mirrorAllowed
                          ? linkedCalendarEventsRepository
                              .watchLinkedEvents(dataCg)
                          : Stream<List<LinkedCalendarEvent>>.value(
                              const <LinkedCalendarEvent>[],
                            ),
                      builder: (context, linkSnap) {
                        return StreamBuilder<List<CareGroupMedication>>(
                          stream: medicationsRepository.isAvailable
                              ? medicationsRepository.watchMedications(dataCg)
                              : Stream<List<CareGroupMedication>>.value(
                                  const <CareGroupMedication>[],
                                ),
                          builder: (context, medSnap) {
                            final me = membersByUid[currentUserUid];
                            final watchExpenses = expensesRepository.isAvailable &&
                                _canViewExpenseHistory(me);
                            return StreamBuilder<List<CareGroupExpense>>(
                              stream: watchExpenses
                                  ? expensesRepository.watchExpenses(dataCg)
                                  : Stream<List<CareGroupExpense>>.value(
                                      const <CareGroupExpense>[],
                                    ),
                              builder: (context, expSnap) {
                                final meds = (medSnap.hasError &&
                                        medicationsRepository.isAvailable)
                                    ? const <CareGroupMedication>[]
                                    : (medSnap.data ?? const []);
                                final exps = (expSnap.hasError &&
                                        watchExpenses)
                                    ? const <CareGroupExpense>[]
                                    : (expSnap.data ?? const []);

                                final lanes = _buildQuarterUpcomingLanes(
                                  tasks: taskSnap.data ?? const [],
                                  meetings: meetSnap.data ?? const [],
                                  linkedGcalEvents: mirrorAllowed
                                      ? (linkSnap.data ?? const [])
                                      : const <LinkedCalendarEvent>[],
                                  medications: meds,
                                  expenses: exps,
                                );
                                final calendarErr = (meetSnap.hasError &&
                                        meetingsRepository.isAvailable) ||
                                    (mirrorAllowed &&
                                        linkSnap.hasError &&
                                        linkedCalendarEventsRepository
                                            .isAvailable);
                                final tasksErr = taskSnap.hasError &&
                                    taskRepository.isAvailable;
                                final medsErr = medSnap.hasError &&
                                    medicationsRepository.isAvailable;
                                final expensesErr = expSnap.hasError &&
                                    watchExpenses;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: _homeOrderedLandingSectionWidgets(
                                    context: context,
                                    sections: homeSections,
                                    memberListCareGroupId: membersCg,
                                    dataCareGroupId: dataCg,
                                    currentUserUid: currentUserUid,
                                    membersRepository: membersRepository,
                                    taskRepository: taskRepository,
                                    chatRepository: chatRepository,
                                    journalRepository: journalRepository,
                                    notesRepository: notesRepository,
                                    nameByUid: byUid,
                                    membersByUid: membersByUid,
                                    lanes: lanes,
                                    calendarErr: calendarErr,
                                    tasksErr: tasksErr,
                                    medicationsErr: medsErr,
                                    expensesErr: expensesErr,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _UpcomingCompactCard extends StatelessWidget {
  const _UpcomingCompactCard({
    required this.item,
    required this.nameByUid,
    required this.membersByUid,
    required this.onTap,
  });

  final _UpcomingScheduleItem item;
  final Map<String, String> nameByUid;
  final Map<String, CareGroupMember> membersByUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final kind = item.kind;

    late final IconData icon;
    late final String kindLabel;
    late final Color accent;
    late final String title;
    late final String subtitle;
    String? avatarUid;
    var titleMaxLines = 2;

    switch (kind) {
      case _UpcomingKind.task:
        final t = item.task!;
        icon = Icons.task_alt_outlined;
        kindLabel = "Task";
        accent = _urgencyBarColor(t, onTrackColor: s.outlineAccent);
        title = t.title.isEmpty ? "Task" : t.title;
        subtitle = _formatTaskDueLine(t.dueAt);
        avatarUid = t.assignedTo;
        break;
      case _UpcomingKind.meeting:
        final m = item.meeting!;
        icon = Icons.groups_2_outlined;
        kindLabel = "Meeting";
        accent = const Color(0xFF1A7F7A);
        title = m.title.isEmpty ? "Meeting" : m.title;
        subtitle = _formatTaskDueLine(m.meetingAt);
        avatarUid = m.createdBy.isNotEmpty ? m.createdBy : null;
        break;
      case _UpcomingKind.linkedGcal:
        final e = item.linked!;
        icon = Icons.calendar_month_outlined;
        kindLabel = "Calendar";
        accent = const Color(0xFF8E24AA);
        title = e.title.isEmpty ? "Event" : e.title;
        subtitle = _formatTaskDueLine(e.startAt);
        break;
      case _UpcomingKind.medication:
        final meds = item.medications!;
        icon = Icons.medication_outlined;
        kindLabel = meds.length > 1 ? "Medicines" : "Medicine";
        accent = const Color(0xFF0277BD);
        if (meds.length == 1) {
          final med = meds.first;
          title = med.name.isEmpty ? "Medication" : med.name;
        } else {
          titleMaxLines = 3;
          final names = meds
              .map((m) => m.name.trim().isEmpty ? "Medication" : m.name.trim())
              .toList();
          const maxInTitle = 3;
          if (names.length <= maxInTitle) {
            title = names.join(", ");
          } else {
            title =
                "${names.take(maxInTitle).join(", ")} +${names.length - maxInTitle} more";
          }
        }
        subtitle = _formatTaskDueLine(item.sortAt);
        break;
      case _UpcomingKind.expense:
        final ex = item.expense!;
        icon = Icons.payments_outlined;
        kindLabel = "Expense";
        accent = const Color(0xFFC2185B);
        title = ex.title.isEmpty ? "Expense" : ex.title;
        subtitle =
            "${formatCurrencyAmount(ex.amount, ex.currency)} · ${_formatTaskDueLine(ex.spentAt)}";
        avatarUid = ex.createdBy.isNotEmpty ? ex.createdBy : null;
        break;
    }

    final avatarKey =
        avatarUid != null && avatarUid.isNotEmpty ? avatarUid : null;
    final assigneeName =
        avatarKey != null ? _nameForUid(avatarKey, nameByUid) : null;

    return SizedBox(
      width: 156,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: s.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: s.cardShadow,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 36,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 13, color: s.textMuted),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  kindLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                    color: s.textMuted,
                                  ),
                                ),
                              ),
                              if (avatarKey != null)
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: kind == _UpcomingKind.expense &&
                                          membersByUid[avatarKey] != null
                                      ? CareUserAvatar(
                                          radius: 11,
                                          profile:
                                              _userProfileFromCareGroupMember(
                                            membersByUid[avatarKey]!,
                                          ),
                                        )
                                      : Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: _avatarColor(avatarKey),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            _initialsForName(
                                              (assigneeName != null &&
                                                      assigneeName.isNotEmpty)
                                                  ? assigneeName
                                                  : "?",
                                            ),
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w700,
                                              color: _onAvatar(
                                                _avatarColor(avatarKey),
                                                fallback: s.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: titleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: s.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.15,
                              color: s.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UrgentTasksSection extends StatelessWidget {
  const _UrgentTasksSection({
    required this.memberListCareGroupId,
    required this.dataCareGroupId,
    required this.membersRepository,
    required this.taskRepository,
  });

  /// `careGroups/{id}/members` (user’s membership document).
  final String? memberListCareGroupId;

  /// `careGroups/{id}/tasks` (linked home when the app uses two docs).
  final String? dataCareGroupId;
  final MembersRepository membersRepository;
  final TaskRepository taskRepository;

  @override
  Widget build(BuildContext context) {
    if (memberListCareGroupId == null ||
        memberListCareGroupId!.isEmpty ||
        dataCareGroupId == null ||
        dataCareGroupId!.isEmpty ||
        !taskRepository.isAvailable ||
        !membersRepository.isAvailable) {
      return const SizedBox.shrink();
    }
    final membersCg = memberListCareGroupId!;
    final dataCg = dataCareGroupId!;
    return StreamBuilder<List<CareGroupMember>>(
      stream:
          membersRepository.watchMembersOrRoster(membersCg, dataCareGroupId),
      builder: (context, memSnap) {
        final byUid = {
          for (final m in memSnap.data ?? <CareGroupMember>[])
            m.userId: m.displayName,
        };
        return StreamBuilder<List<CareGroupTask>>(
          stream: taskRepository.watchTasks(dataCg),
          builder: (context, taskSnap) {
            if (taskSnap.hasError) {
              return Text(
                "Tasks could not be loaded.",
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              );
            }
            final urgent = _urgentOpenTasksFirst(taskSnap.data ?? const []);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  title: "Urgent tasks",
                  onSeeAll: () => context.push("/tasks"),
                  seeAllLabel: "View all →",
                ),
                const SizedBox(height: 8),
                if (urgent.isEmpty)
                  Text(
                    "No open tasks right now.",
                    style: TextStyle(
                      fontSize: 12,
                      color: CareGroupHomeStyleScope.of(context).textMuted,
                    ),
                  )
                else
                  ...urgent.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _UrgentTaskRow(
                        task: t,
                        nameByUid: byUid,
                        onTap: () {
                          final u = Uri(
                            path: "/tasks",
                            queryParameters: {
                              "taskId": t.id,
                            },
                          );
                          context.push(u.toString());
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _UrgentTaskRow extends StatelessWidget {
  const _UrgentTaskRow({
    required this.task,
    required this.nameByUid,
    required this.onTap,
  });

  final CareGroupTask task;
  final Map<String, String> nameByUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final unassigned = task.assignedTo == null || task.assignedTo!.isEmpty;
    final assigneeName = _nameForUid(task.assignedTo, nameByUid);
    final firstName = assigneeName.split(" ").first;
    final bar = _urgencyBarColor(task, onTrackColor: s.outlineAccent);
    return Opacity(
      opacity: unassigned ? 0.65 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: unassigned ? s.cardBorderUnassigned : s.cardBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: s.cardShadow,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(0, 11, 10, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: 44,
                  margin: const EdgeInsets.only(left: 4, right: 10),
                  decoration: BoxDecoration(
                    color: bar,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title.isEmpty ? "Task" : task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: s.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            _formatTaskDueLine(task.dueAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: s.textMuted,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 2,
                            decoration: BoxDecoration(
                              color: s.timeMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (unassigned)
                            const Text(
                              "Needs owner",
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFC0392B),
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else ...[
                            Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _avatarColor(task.assignedTo!),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                _initialsForName(assigneeName),
                                style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w700,
                                  color: _onAvatar(
                                    _avatarColor(task.assignedTo!),
                                    fallback: s.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              firstName,
                              style: TextStyle(
                                fontSize: 10,
                                color: s.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: s.timeMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentActivitySection extends StatefulWidget {
  const _RecentActivitySection({
    required this.memberListCareGroupId,
    required this.dataCareGroupId,
    required this.membersRepository,
    required this.journalRepository,
    required this.notesRepository,
    required this.taskRepository,
  });

  final String? memberListCareGroupId;
  final String? dataCareGroupId;
  final MembersRepository membersRepository;
  final JournalRepository journalRepository;
  final NotesRepository notesRepository;
  final TaskRepository taskRepository;

  @override
  State<_RecentActivitySection> createState() => _RecentActivitySectionState();
}

class _RecentActivitySectionState extends State<_RecentActivitySection> {
  late Stream<List<JournalEntry>> _journalStream;
  late Stream<List<CareGroupNote>> _notesStream;
  late Stream<List<CareGroupTask>> _tasksStream;

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  @override
  void didUpdateWidget(covariant _RecentActivitySection old) {
    super.didUpdateWidget(old);
    if (old.dataCareGroupId != widget.dataCareGroupId ||
        old.memberListCareGroupId != widget.memberListCareGroupId) {
      _bindStreams();
    }
  }

  void _bindStreams() {
    final id = widget.dataCareGroupId;
    if (id == null || id.isEmpty) {
      _journalStream = Stream<List<JournalEntry>>.value(const <JournalEntry>[]);
      _notesStream = Stream<List<CareGroupNote>>.value(const <CareGroupNote>[]);
      _tasksStream = Stream<List<CareGroupTask>>.value(const <CareGroupTask>[]);
      return;
    }
    _journalStream = widget.journalRepository.isAvailable
        ? widget.journalRepository.watchJournal(id)
        : Stream<List<JournalEntry>>.value(const <JournalEntry>[]);
    _notesStream = widget.notesRepository.isAvailable
        ? widget.notesRepository.watchNotes(id)
        : Stream<List<CareGroupNote>>.value(const <CareGroupNote>[]);
    _tasksStream = widget.taskRepository.isAvailable
        ? widget.taskRepository.watchTasks(id)
        : Stream<List<CareGroupTask>>.value(const <CareGroupTask>[]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.memberListCareGroupId == null ||
        widget.memberListCareGroupId!.isEmpty ||
        widget.dataCareGroupId == null ||
        widget.dataCareGroupId!.isEmpty ||
        !widget.membersRepository.isAvailable) {
      return const SizedBox.shrink();
    }
    final anySource = widget.journalRepository.isAvailable ||
        widget.notesRepository.isAvailable ||
        widget.taskRepository.isAvailable;
    if (!anySource) {
      return const SizedBox.shrink();
    }
    final membersCg = widget.memberListCareGroupId!;

    return StreamBuilder<List<CareGroupMember>>(
      stream: widget.membersRepository.watchMembersOrRoster(
        membersCg,
        widget.dataCareGroupId,
      ),
      builder: (context, memSnap) {
        final byUid = {
          for (final m in memSnap.data ?? <CareGroupMember>[])
            m.userId: m.displayName,
        };
        return StreamBuilder<List<JournalEntry>>(
          stream: _journalStream,
          builder: (context, jSnap) {
            return StreamBuilder<List<CareGroupNote>>(
              stream: _notesStream,
              builder: (context, nSnap) {
                return StreamBuilder<List<CareGroupTask>>(
                  stream: _tasksStream,
                  builder: (context, tSnap) {
                    if (jSnap.hasError || nSnap.hasError || tSnap.hasError) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionHeader(title: "Recent activity"),
                          const SizedBox(height: 8),
                          Text(
                            "Activity could not be loaded.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      );
                    }
                    final items = _buildActivityRowModels(
                      context,
                      journal: jSnap.data ?? const [],
                      notes: nSnap.data ?? const [],
                      tasks: tSnap.data ?? const [],
                      nameByUid: byUid,
                    );
                    final s = CareGroupHomeStyleScope.of(context);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                "Recent activity",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: s.textPrimary,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.more_horiz,
                                size: 22,
                                color: s.textMuted,
                              ),
                              onSelected: (v) {
                                if (v == "j") {
                                  context.push("/journal");
                                } else if (v == "n") {
                                  context.push("/notes");
                                } else if (v == "t") {
                                  context.push("/tasks");
                                } else if (v == "e") {
                                  context.push("/expenses");
                                }
                              },
                              itemBuilder: (c) => const [
                                PopupMenuItem(
                                  value: "j",
                                  child: Text("Open journal"),
                                ),
                                PopupMenuItem(
                                  value: "n",
                                  child: Text("Open notes"),
                                ),
                                PopupMenuItem(
                                  value: "t",
                                  child: Text("Open tasks"),
                                ),
                                PopupMenuItem(
                                  value: "e",
                                  child: Text("Open expenses"),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: s.feedBorder),
                            boxShadow: [
                              BoxShadow(
                                color: s.cardShadow,
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: items.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    "Nothing recent yet. Add a journal handover, a note, or a task.",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: s.textMuted,
                                      height: 1.5,
                                    ),
                                  ),
                                )
                              : Column(
                                  children: [
                                    for (var i = 0; i < items.length; i++) ...[
                                      _ActivityFeedRow(model: items[i]),
                                      if (i < items.length - 1)
                                        Divider(
                                          height: 1,
                                          color: s.dividerSubtle,
                                        ),
                                    ],
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ActivityFeedRow extends StatelessWidget {
  const _ActivityFeedRow({required this.model});

  final _ActivityRowModel model;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final bg = _avatarColor(model.authorUid);
    final fg = _onAvatar(bg, fallback: s.textPrimary);
    return InkWell(
      onTap: model.onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
              ),
              child: Text(
                _initialsForName(model.authorName),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 11,
                    color: s.textMuted,
                    height: 1.5,
                  ),
                  children: [
                    TextSpan(
                      text: model.authorName,
                      style: TextStyle(
                        color: s.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: " — "),
                    TextSpan(
                      text: model.kindLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: s.textTertiary,
                      ),
                    ),
                    const TextSpan(text: " · "),
                    TextSpan(
                      text: "“${model.quoted}”",
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _formatRelativeAgo(model.shownTime),
              style: TextStyle(
                fontSize: 10,
                color: s.timeMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCta extends StatelessWidget {
  const _AddCta({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final on = s.onAddCta;
    return Material(
      color: s.addCta,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "+",
                  style: TextStyle(
                    color: on,
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Add task, note, photo…",
                style: TextStyle(
                  color: on,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartSetupBanner extends StatelessWidget {
  const _StartSetupBanner({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final a = s.outlineAccent;
    return Material(
      color: s.wizardBannerBackground,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Set up your care group",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "Complete the short setup wizard to create your team. "
              "Then you can use tasks, chat, calendar, medications, and more on the home page.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: a,
                foregroundColor: a.computeLuminance() < 0.45
                    ? const Color(0xFFF5F0EA)
                    : const Color(0xFF1A1816),
              ),
              onPressed: onStart,
              child: const Text("Start setup"),
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardBanner extends StatelessWidget {
  const _WizardBanner({required this.onContinue});
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final s = CareGroupHomeStyleScope.of(context);
    final a = s.outlineAccent;
    return Material(
      color: s.wizardBannerBackground,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Finish setting up CareShare",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "You skipped the setup wizard. Continue when you are ready so your care group, pathways, and invites are configured.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: a,
                foregroundColor: a.computeLuminance() < 0.45
                    ? const Color(0xFFF5F0EA)
                    : const Color(0xFF1A1816),
              ),
              onPressed: onContinue,
              child: const Text("Continue setup"),
            ),
          ],
        ),
      ),
    );
  }
}
