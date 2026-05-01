import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/care/role_label.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_event.dart";
import "../../care_group/models/care_group_option.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../models/user_profile.dart";
import "widgets/care_user_avatar.dart";

void showUserAccountMenu(
  BuildContext context, {
  required UserProfile signedInIdentity,
  required ProfileState profileState,
}) {
  final ready = profileState is ProfileReady ? profileState : null;
  final p = ready?.profile;
  final title = p != null && p.displayName.isNotEmpty
      ? p.displayName
      : (signedInIdentity.displayName.trim().isNotEmpty
          ? signedInIdentity.displayName
          : (signedInIdentity.email.split("@").first));
  final sub = p != null && p.email.isNotEmpty
      ? p.email
      : signedInIdentity.email;
  final careGroupOptions = ready?.careGroupOptions ?? const <CareGroupOption>[];
  final hasMultipleCareGroups = careGroupOptions.length > 1;
  final activeCareGroupId = ready?.profile.activeCareGroupId;
  final activeCareGroupName = ready?.activeCareGroupDisplayName;

  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CareUserAvatar(
                    radius: 28,
                    profile: p,
                    authFallback: signedInIdentity,
                  ),
                  title: Text(title),
                  subtitle: sub.isNotEmpty
                      ? Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                ),
                if (p != null) const Divider(),
                if (p != null) ...[
                  ListTile(
                    leading: const Icon(Icons.dashboard_customize_outlined),
                    title: const Text("Homepage sections"),
                    subtitle: const Text(
                      "Today's needs, previews, urgent tasks, and activity",
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.push("/user-settings/homepage");
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text("Alerts & channels"),
                    subtitle: const Text(
                      "Medication reorder reminders: in-app, email, push, SMS",
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.push("/user-settings/alerts");
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.face_outlined),
                    title: const Text("Profile & avatar"),
                    subtitle:
                        const Text("Display name, photo, or a preset image"),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.push("/user-settings/profile");
                    },
                  ),
                  if (hasMultipleCareGroups) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.swap_horiz_outlined,
                            size: 18,
                            color:
                                Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Switch care group",
                            style: Theme.of(ctx).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    ...careGroupOptions.map(
                      (CareGroupOption o) {
                        final isActive = o.careGroupId == activeCareGroupId;
                        return ListTile(
                          leading: Icon(
                            isActive
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isActive
                                ? Theme.of(ctx).colorScheme.primary
                                : Theme.of(ctx).colorScheme.outline,
                          ),
                          title: Text(
                            o.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: _CareGroupRoleChips(roles: o.roles),
                          trailing: isActive
                              ? Text(
                                  "Active",
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .primary,
                                      ),
                                )
                              : null,
                          onTap: isActive
                              ? null
                              : () async {
                                  Navigator.of(ctx).pop();
                                  final cubit = context.read<ProfileCubit>();
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  try {
                                    await cubit.selectActiveCareGroup(o);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Active care group is now: ${o.displayName}",
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                          content: Text(e.toString())),
                                    );
                                  }
                                },
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.more_horiz),
                      title: const Text("Open full care group switcher…"),
                      subtitle: Text(
                        activeCareGroupName != null &&
                                activeCareGroupName.isNotEmpty
                            ? "Active: $activeCareGroupName"
                            : "Choose a different care team",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        context.push("/select-care-group?picker=1");
                      },
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    leading: const Icon(Icons.groups_2_outlined),
                    title: const Text("Care groups & roles"),
                    subtitle: const Text(
                        "Switch your active care team, see your roles"),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.push("/user-settings/care-groups");
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text("Email & security"),
                  subtitle: p != null
                      ? const Text("Password, sign-in methods, and your email")
                      : const Text(
                          "Sign-in, password, and your email on this account"),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push("/user-settings/security");
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.logout,
                      color: Theme.of(ctx).colorScheme.error),
                  title: Text(
                    "Log out",
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.read<AuthBloc>().add(const AuthSignOutRequested());
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Small, muted role chips shown under a care group's name in the avatar menu's
/// inline "Switch care group" list. Mirrors the role text used in
/// `UserSettingsCareGroupsScreen` via [careGroupRoleLabel].
class _CareGroupRoleChips extends StatelessWidget {
  const _CareGroupRoleChips({required this.roles});

  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (roles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          "Role not set on your membership",
          style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final role in roles)
            Chip(
              label: Text(careGroupRoleLabel(role)),
              labelStyle: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.onSecondaryContainer,
              ),
              backgroundColor: t.colorScheme.secondaryContainer,
              side: BorderSide.none,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            ),
        ],
      ),
    );
  }
}
