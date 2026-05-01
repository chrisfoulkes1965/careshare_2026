import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../care_group/models/care_group_option.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "widgets/care_group_calendar_setup_section.dart";
import "widgets/care_group_members_invites_section.dart";
import "widgets/care_group_theme_picker_sheet.dart";
import "../../settings/view/widgets/calendar_subscription_tile.dart";
import "../models/home_sections_visibility.dart";

/// Settings for the user’s [ProfileReady.profile.activeCareGroupId]: name, theme, setup wizard, members.
void _careGroupSettingsPopOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go("/home");
  }
}

class CareGroupSettingsScreen extends StatelessWidget {
  const CareGroupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final opt = state.activeCareGroupOption;
        if (opt == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text("Care group"),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _careGroupSettingsPopOrHome(context),
              ),
            ),
            body: _NoActiveGroupBody(
              hasCareGroups: state.careGroupOptions.isNotEmpty,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              opt.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _careGroupSettingsPopOrHome(context),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionHeader(text: "Name & theme"),
              const SizedBox(height: 8),
              _CareGroupSettingsForm(option: opt),
              const SizedBox(height: 32),
              const _SectionHeader(text: "Homepage"),
              const SizedBox(height: 8),
              _CareGroupHomepageSectionsCard(option: opt),
              if (state.profile.wizardCompleted) ...[
                const SizedBox(height: 32),
                const _SectionHeader(text: "Setup wizard"),
                const SizedBox(height: 8),
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Re-run the guided setup. If you finish it, a new care group and home may be created — use this only when you mean to.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Run setup again?"),
                              content: const Text(
                                "You will go through the setup steps again. If you complete it, a new care group and home can be created — use this only if you understand that. For small changes, care group settings are a better place.",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text("Cancel"),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    context.push("/setup?edit=1");
                                  },
                                  child: const Text("Continue"),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings_suggest_outlined),
                        label: const Text("Open setup wizard"),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              const _SectionHeader(text: "People & invites"),
              const SizedBox(height: 8),
              _SectionCard(
                child: CareGroupMembersInvitesSection(option: opt),
              ),
              const SizedBox(height: 32),
              const _SectionHeader(text: "Care groups"),
              const SizedBox(height: 8),
              _SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.swap_horiz_outlined),
                  title: const Text("Switch care group"),
                  subtitle: const Text(
                      "Choose a different care team or review all of yours"),
                  onTap: () {
                    if (context.mounted) {
                      context.push("/user-settings/care-groups");
                    }
                  },
                ),
              ),
              const SizedBox(height: 32),
              const _SectionHeader(text: "Calendar"),
              const SizedBox(height: 8),
              _SectionCard(
                child: CareGroupCalendarSetupSection(option: opt),
              ),
              const SizedBox(height: 12),
              const _SectionCard(
                child: CalendarSubscriptionTile(),
              ),
              const SizedBox(height: 32),
              const _SectionHeader(text: "Active IDs"),
              const SizedBox(height: 8),
              _ActiveIdsForSupportBody(
                activeCareGroupId: state.profile.activeCareGroupId,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CareGroupSettingsForm extends StatefulWidget {
  const _CareGroupSettingsForm({required this.option});

  final CareGroupOption option;

  @override
  State<_CareGroupSettingsForm> createState() => _CareGroupSettingsFormState();
}

class _CareGroupSettingsFormState extends State<_CareGroupSettingsForm> {
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.option.displayName);
  }

  @override
  void didUpdateWidget(covariant _CareGroupSettingsForm old) {
    super.didUpdateWidget(old);
    if (old.option.careGroupId != widget.option.careGroupId) {
      _name.text = widget.option.displayName;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.option;
    final canEditAppearance = o.canEditCareGroupNameThemeAndCalendar;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Name this care team and set the theme colour for home. "
            "Only a care group administrator can change the name, theme colour, linked calendar settings, "
            "and which homepage sections are available to the team.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            readOnly: !canEditAppearance,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Care group name",
              hintText: "Name shown in the app",
              enabled: canEditAppearance,
              suffixIcon: canEditAppearance && _saving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (canEditAppearance) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final t = _name.text.trim();
                      if (t.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Enter a name.")),
                        );
                        return;
                      }
                      setState(() => _saving = true);
                      final ms = ScaffoldMessenger.of(context);
                      try {
                        await context.read<ProfileCubit>().updateCareGroupName(
                              o.careGroupId,
                              t,
                            );
                        if (context.mounted) {
                          ms.showSnackBar(
                            const SnackBar(content: Text("Name updated")),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ms.showSnackBar(
                              SnackBar(content: Text(e.toString())));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _saving = false);
                        }
                      }
                    },
              child: const Text("Save name"),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "Ask a care group administrator to change the name or theme colour.",
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.grey500,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            "Theme colour",
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            "Sets the header, background, and accent colours for home for this care group.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: o.themeColor != null
                    ? Color(o.themeColor!)
                    : const Color(0xFF3B2A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            title: const Text("Theme colour…"),
            subtitle: const Text("Tap to choose a colour or reset to default"),
            onTap: canEditAppearance
                ? () => _onPickTheme(context, o)
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            "Only a care group administrator can change the theme colour."),
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _onPickTheme(BuildContext context, CareGroupOption o) async {
    final result = await showCareGroupThemePicker(
      context,
      currentArgb: o.themeColor,
    );
    if (!context.mounted || result == null) {
      return;
    }
    final ms = ScaffoldMessenger.of(context);
    try {
      if (result == "reset") {
        await context.read<ProfileCubit>().setCareGroupThemeColor(
              o.careGroupId,
              null,
            );
      } else if (result is int) {
        await context.read<ProfileCubit>().setCareGroupThemeColor(
              o.careGroupId,
              result,
            );
      }
      if (context.mounted) {
        ms.showSnackBar(
          const SnackBar(content: Text("Theme colour updated")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ms.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class _CareGroupHomepageSectionsCard extends StatelessWidget {
  const _CareGroupHomepageSectionsCard({required this.option});

  final CareGroupOption option;

  Future<void> _apply(
    BuildContext context,
    HomeSectionsVisibility next,
  ) async {
    try {
      await context.read<ProfileCubit>().setCareGroupHomepageSectionsPolicy(
            dataCareGroupDocId: option.dataCareGroupId,
            policy: next,
          );
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
    final canEdit = option.canEditCareGroupNameThemeAndCalendar;
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        var o = option;
        if (state is ProfileReady) {
          for (final x in state.careGroupOptions) {
            if (x.careGroupId == option.careGroupId) {
              o = x;
              break;
            }
          }
        }
        final policy =
            o.homepageSectionsPolicy ?? const HomeSectionsVisibility();
        final ordered = HomeSectionId.canonicalOrder;

        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                canEdit
                    ? "Turn sections off to hide them from everyone’s home for this care group. "
                        "Members can still personalize order and which allowed sections they see."
                    : "Only a care group administrator can choose which sections are available on home. "
                        "You can still hide allowed sections for yourself under Account → Homepage sections.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (canEdit) ...[
                const SizedBox(height: 12),
                for (final id in ordered) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_title(id)),
                    subtitle: Text(_subtitle(id)),
                    value: _visibilityFor(policy, id),
                    onChanged: (on) => _apply(context, _copyVisibility(policy, id, on)),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    try {
                      await context
                          .read<ProfileCubit>()
                          .clearCareGroupHomepageSectionsPolicy(
                            o.dataCareGroupId,
                          );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "All homepage sections are allowed again for this group.",
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  },
                  child: const Text("Allow all sections (reset group default)"),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoActiveGroupBody extends StatelessWidget {
  const _NoActiveGroupBody({required this.hasCareGroups});

  final bool hasCareGroups;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 48,
                color: t.colorScheme.outline,
              ),
              const SizedBox(height: 20),
              Text(
                "No active care team yet",
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                hasCareGroups
                    ? "You belong to at least one care team, but none is set as the active one. "
                        "Choose which team you want to work with, then you can change its name, "
                        "theme colour, and who is on the team."
                    : "This screen changes settings for a specific care team. When you are part of a team, pick it here first, "
                        "or accept an invitation if you were invited to care for someone.",
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (context.mounted) {
                    context.push("/user-settings/care-groups");
                  }
                },
                child: const Text("Choose or switch care group"),
              ),
              if (hasCareGroups) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    if (context.mounted) {
                      context.push("/select-care-group?picker=1");
                    }
                  },
                  child: const Text("Open care group switcher"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveIdsForSupportBody extends StatelessWidget {
  const _ActiveIdsForSupportBody({required this.activeCareGroupId});

  final String? activeCareGroupId;

  void _copyId(BuildContext context) {
    final v = activeCareGroupId;
    if (v == null || v.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: v));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Care group id copied")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "For support or debugging — copy the id if asked.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _IdRow(
            label: "Care group",
            value: activeCareGroupId,
            onCopy: () => _copyId(context),
          ),
        ],
      ),
    );
  }
}

class _IdRow extends StatelessWidget {
  const _IdRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String? value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final v = value?.isNotEmpty == true ? value! : "—";
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (value != null && value!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: onCopy,
            tooltip: "Copy",
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}
