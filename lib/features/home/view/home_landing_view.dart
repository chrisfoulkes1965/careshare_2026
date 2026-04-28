import "package:firebase_auth/firebase_auth.dart" show User;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/care/role_label.dart";
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
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../../setup_wizard/repository/setup_repository.dart";
import "../../tasks/models/care_group_task.dart";
import "../../tasks/repository/task_repository.dart";
import "../../user/view/user_account_menu.dart";
import "../../user/view/widgets/care_user_avatar.dart";

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
  return all
      .where((m) => m.roles.contains("receives_care"))
      .take(4)
      .toList();
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

/// Care group “landing” layout inspired by the warm homepage mockup.
class HomeLandingView extends StatelessWidget {
  const HomeLandingView({
    super.key,
    required this.pr,
    required this.user,
    required this.email,
    required this.showWizardBanner,
  });

  final ProfileReady pr;
  final User? user;
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
                  user: user,
                  email: email,
                  groupName: groupName,
                  name: name,
                  headerStyle: headerStyle,
                  onOpenTool: (path) => context.push(path),
                ),
                const SizedBox(height: 8),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  child: _TodayNeedsSection(
                    careGroupId: memberDocId,
                    dataCareGroupId: dataId,
                    membersRepository: context.read<MembersRepository>(),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  child: _UrgentTasksSection(
                    memberListCareGroupId: memberDocId,
                    dataCareGroupId: dataId,
                    membersRepository: context.read<MembersRepository>(),
                    taskRepository: context.read<TaskRepository>(),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _RecentActivitySection(
                    memberListCareGroupId: memberDocId,
                    dataCareGroupId: dataId,
                    membersRepository: context.read<MembersRepository>(),
                    journalRepository: context.read<JournalRepository>(),
                    notesRepository: context.read<NotesRepository>(),
                    taskRepository: context.read<TaskRepository>(),
                  ),
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
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Add to your care team",
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: const Text("New task"),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push("/tasks");
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_alt_outlined),
                title: const Text("Add to notes"),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push("/notes");
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.pr,
    required this.user,
    required this.email,
    required this.groupName,
    required this.name,
    required this.headerStyle,
    required this.onOpenTool,
  });

  final ProfileReady pr;
  final User? user;
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
                                    color: s.toolBarChips[i].background,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                    _kCareTeamTools[i].$1,
                                    size: 18,
                                    color: s.toolBarChips[i].iconColor,
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
                  if (user != null)
                    SizedBox(
                      width: headerActionSize,
                      height: headerActionSize,
                      child: Center(
                        child: Material(
                          color:
                              h.avatarMaterialColor ?? const Color(0xFF6B4D35),
                          shape: CircleBorder(
                            side: BorderSide(
                              color: h.avatarRingColor ??
                                  const Color(0xFF8C6E55),
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              showUserAccountMenu(
                                context,
                                user: user!,
                                profileState: pr,
                              );
                            },
                            customBorder: const CircleBorder(),
                            child: CareUserAvatar(
                              radius: 20,
                              user: user!,
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
  (Icons.menu_book_outlined, "Journal", "/journal"),
  (Icons.contact_phone_outlined, "Contacts", "/contacts"),
  (Icons.payments_outlined, "Expenses", "/expenses"),
  (Icons.groups_2_outlined, "Meetings", "/meetings"),
  (Icons.forum_outlined, "Chat", "/chat"),
];

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
      stream: membersRepository.watchMembersOrRoster(membersCg, dataCareGroupId),
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
                "Add a task or note",
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

