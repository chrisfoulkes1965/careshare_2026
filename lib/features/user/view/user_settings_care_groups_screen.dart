import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/care/role_label.dart";
import "../../care_group/models/care_group_option.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";

class UserSettingsCareGroupsScreen extends StatelessWidget {
  const UserSettingsCareGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = state.profile;
        final options = state.careGroupOptions;
        final active = profile.activeCareGroupId;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Care groups & roles"),
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
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                "You appear in the member list of each of these care teams. "
                "Roles are how this home can tell what you are allowed to do. "
                "To change someone else’s role, a principal or organiser can update members. "
                "Name, theme colour, and members for the active care group: open care group on home, or the button below.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () {
                  if (context.mounted) {
                    context.push("/user-settings/care-group");
                  }
                },
                child: const Text("Active care group settings…"),
              ),
              const SizedBox(height: 16),
              if (options.isEmpty)
                const Text(
                  "No care groups were found. Complete setup or accept an invite.",
                )
              else
                ...options.map(
                  (CareGroupOption o) => _CareGroupRow(
                    option: o,
                    isActive: o.careGroupId == active,
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  if (context.mounted) {
                    context.push("/select-care-group?picker=1");
                  }
                },
                child: const Text("Open care group switcher…"),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CareGroupRow extends StatelessWidget {
  const _CareGroupRow({required this.option, required this.isActive});

  final CareGroupOption option;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final roleText = option.roles.isEmpty
        ? "Role not set on your membership"
        : option.roles.map(careGroupRoleLabel).join(" · ");
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(option.displayName),
        subtitle: Text(roleText),
        trailing: isActive
            ? const InputChip(
                label: Text("Active"),
                onPressed: null,
                visualDensity: VisualDensity.compact,
              )
            : TextButton(
                onPressed: () async {
                  final cubit = context.read<ProfileCubit>();
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await cubit.selectActiveCareGroup(option);
                    if (context.mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            "Active care group is now: ${option.displayName}",
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  }
                },
                child: const Text("Switch to"),
              ),
      ),
    );
  }
}
