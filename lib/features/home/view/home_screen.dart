import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";
import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../../setup_wizard/repository/setup_repository.dart";
import "../../user/view/user_account_menu.dart";
import "../../user/view/widgets/care_user_avatar.dart";

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _copy(BuildContext context, String label, String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$label copied")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profileState) {
        return BlocBuilder<AuthBloc, AuthState>(
          buildWhen: (p, c) => p.user?.uid != c.user?.uid,
          builder: (context, authState) {
            final user = authState.user;
            final email = user?.email ?? "Signed in";

            return Scaffold(
              appBar: AppBar(
                title: const Text(AppConstants.appName),
                actions: [
                  IconButton(
                    tooltip: "Refresh profile",
                    onPressed: () => context.read<ProfileCubit>().refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                  if (user != null)
                    IconButton(
                      tooltip: "Account and settings",
                      onPressed: () {
                        showUserAccountMenu(
                          context,
                          user: user,
                          profileState: profileState,
                        );
                      },
                      icon: CareUserAvatar(
                        radius: 18,
                        user: user,
                        profile: profileState is ProfileReady
                            ? profileState.profile
                            : null,
                      ),
                    ),
                ],
              ),
              body: SafeArea(
                child: Builder(
                  builder: (context) {
                    if (profileState is ProfileLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (profileState is ProfileError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                profileState.message,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () =>
                                    context.read<ProfileCubit>().refresh(),
                                child: const Text("Retry"),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final ready = profileState is ProfileReady;
                    final profile = ready ? profileState.profile : null;
                    final banner = ready &&
                        profile!.wizardSkipped &&
                        !profile.wizardCompleted;

                    final bottomPad = MediaQuery.paddingOf(context).bottom;
                    return ListView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomPad),
                      children: [
                        if (banner) ...[
                          Material(
                            color: AppColors.tealLight,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Finish setting up CareShare",
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "You skipped the setup wizard. Continue when you are ready so your care group, pathways, and invites are configured.",
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: () async {
                                      final uid = context
                                          .read<AuthBloc>()
                                          .state
                                          .user
                                          ?.uid;
                                      if (uid == null) return;
                                      final repo =
                                          context.read<SetupRepository>();
                                      if (repo.isAvailable) {
                                        await repo.resumeWizard(uid);
                                        if (!context.mounted) return;
                                        await context
                                            .read<ProfileCubit>()
                                            .refresh();
                                      }
                                      if (!context.mounted) return;
                                      context.go("/setup");
                                    },
                                    child: const Text("Continue setup"),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          profile != null && profile.displayName.isNotEmpty
                              ? "Hello, ${profile.displayName}"
                              : "Dashboard",
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.grey500,
                                  ),
                        ),
                        if (profileState case final ProfileReady pr
                            when pr.careGroupOptions.length > 1) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  context.push("/select-care-group?picker=1"),
                              icon: const Icon(Icons.swap_horiz_outlined),
                              label: const Text("Switch care group"),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          "Care",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _ActionCard(
                          icon: Icons.task_alt_outlined,
                          title: "Tasks",
                          subtitle:
                              "To-dos and shared work for your care group",
                          onTap: () => context.push("/tasks"),
                        ),
                        _ActionCard(
                          icon: Icons.medication_outlined,
                          title: "Prescriptions & reminders",
                          subtitle:
                              "Store doses and optional photos; get reminders on this device",
                          onTap: () => context.push("/medications"),
                        ),
                        _ActionCard(
                          icon: Icons.route_outlined,
                          title: "Pathways",
                          subtitle:
                              "Care pathways and guidance for your situation",
                          onTap: () => context.push("/pathways"),
                        ),
                        _ActionCard(
                          icon: Icons.mail_outline,
                          title: "Invitations",
                          subtitle:
                              "People you have invited to your care group",
                          onTap: () => context.push("/invitations"),
                        ),
                        _ActionCard(
                          icon: Icons.note_alt_outlined,
                          title: "Notes",
                          subtitle:
                              "Shared context for carers — general, medical, or legal (restricted read)",
                          onTap: () => context.push("/notes"),
                        ),
                        _ActionCard(
                          icon: Icons.menu_book_outlined,
                          title: "Journal",
                          subtitle:
                              "Dated handover log for carers and principal carers (not for care-only access)",
                          onTap: () => context.push("/journal"),
                        ),
                        _ActionCard(
                          icon: Icons.contact_phone_outlined,
                          title: "Contacts",
                          subtitle:
                              "Shared numbers and notes — GPs, nurses, family, and trusted help",
                          onTap: () => context.push("/contacts"),
                        ),
                        _ActionCard(
                          icon: Icons.groups_2_outlined,
                          title: "Meetings",
                          subtitle:
                              "Team and family reviews — date, place, and agenda (not in care-only mode)",
                          onTap: () => context.push("/meetings"),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Care group",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _ActionCard(
                          icon: Icons.groups_outlined,
                          title: "Care group members",
                          subtitle: "People in this care group and their roles",
                          onTap: () => context.push("/members"),
                        ),
                        if (ready && profile != null) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Active IDs (for support / debugging)",
                                    style:
                                        Theme.of(context).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  _IdRow(
                                    label: "Home (data)",
                                    value: profile.activeHouseholdId,
                                    onCopy: () => _copy(
                                      context,
                                      "Home id",
                                      profile.activeHouseholdId ?? "",
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _IdRow(
                                    label: "Care team",
                                    value: profile.activeCareGroupId,
                                    onCopy: () => _copy(
                                      context,
                                      "Care team id",
                                      profile.activeCareGroupId ?? "",
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (profile.wizardCompleted) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Run setup again?"),
                                    content: const Text(
                                      "You will go through the setup steps again. If you complete it, a new care group and home can be created — use this only if you understand that. For small changes, future care group settings will be a better place.",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
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
                        ],
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: AppColors.tealPrimary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
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
