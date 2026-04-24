import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/care/role_label.dart";
import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/members_cubit.dart";
import "../cubit/members_state.dart";
import "../models/care_group_member.dart";
import "../repository/members_repository.dart";

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final cg = state.profile.activeCareGroupId;
        if (cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Care group")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need an active care group to see members. Complete setup or join a care group first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey(cg),
          create: (context) => MembersCubit(
            repository: context.read<MembersRepository>(),
            careGroupId: cg,
          )..subscribe(),
          child: const _MembersView(),
        );
      },
    );
  }
}

class _MembersView extends StatelessWidget {
  const _MembersView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Care group members"),
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
      body: SafeArea(
        child: BlocConsumer<MembersCubit, MembersState>(
          listener: (context, state) {
            if (state is MembersFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is MembersInitial || state is MembersLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is MembersEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "No members in this care group yet.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (state is MembersDisplay) {
              return BlocBuilder<AuthBloc, AuthState>(
                buildWhen: (p, c) => p.user?.uid != c.user?.uid,
                builder: (context, auth) {
                  final selfUid = auth.user?.uid;
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final m = state.list[i];
                      final isSelf = selfUid != null && m.userId == selfUid;
                      return _MemberTile(
                        member: m,
                        highlight: isSelf,
                      );
                    },
                  );
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.highlight,
  });

  final CareGroupMember member;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = member.photoUrl;
    final initial = member.displayName.isNotEmpty
        ? member.displayName[0].toUpperCase()
        : "?";
    return Card(
      color: highlight ? AppColors.tealLight.withValues(alpha: 0.4) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.tealPrimary.withValues(alpha: 0.2),
          foregroundColor: AppColors.tealPrimary,
          child: url != null && url.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    url,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: Text(initial)),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.tealPrimary,
                          ),
                        ),
                      );
                    },
                  ),
                )
              : Text(initial),
        ),
        title: Row(
          children: [
            Expanded(child: Text(member.displayName)),
            if (highlight)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  "You",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.tealPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: member.roles
                  .map(
                    (r) => Chip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(
                        careGroupRoleLabel(r),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (member.joinedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                "Joined ${member.joinedAt!.year}-${member.joinedAt!.month.toString().padLeft(2, "0")}-${member.joinedAt!.day.toString().padLeft(2, "0")}",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.grey500,
                ),
              ),
            ],
            if (member.kudosScore != null) ...[
              const SizedBox(height: 2),
              Text(
                "Kudos ${member.kudosScore}",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.grey500,
                ),
              ),
            ],
          ],
        ),
        isThreeLine: member.joinedAt != null || member.kudosScore != null,
      ),
    );
  }
}
