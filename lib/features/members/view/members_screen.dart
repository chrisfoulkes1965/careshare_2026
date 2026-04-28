import "dart:async";

import "package:firebase_auth/firebase_auth.dart" show User;
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/care/role_label.dart";
import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../../user/models/user_profile.dart";
import "../../user/repository/user_repository.dart";
import "../../user/view/widgets/care_user_avatar.dart";
import "../../invitations/repository/invitation_repository.dart";
import "../cubit/members_cubit.dart";
import "../cubit/members_state.dart";
import "../models/care_group_member.dart";
import "../models/member_deletion_blockers.dart";
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
        final cg = state.activeCareGroupMemberDocId;
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
        final dataId = state.activeCareGroupDataId;
        return BlocProvider(
          key: ObjectKey(cg),
          create: (context) => MembersCubit(
            repository: context.read<MembersRepository>(),
            careGroupId: cg,
            dataCareGroupDocId: dataId,
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
            return BlocBuilder<ProfileCubit, ProfileState>(
              builder: (context, ps) {
                if (ps is! ProfileReady) {
                  return const Center(child: Text("Loading profile…"));
                }
                final isPrincipal =
                    ps.activeCareGroupOption?.isPrincipalCarer == true;
                final dataId = ps.activeCareGroupDataId;
                final inviteCgId = ps.profile.activeCareGroupId ?? dataId;
                if (state is MembersEmpty) {
                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              isPrincipal
                                  ? "No one is listed as a signed-in member yet. Add people below or check pending invitations in care group settings."
                                  : "No members in this care group yet. A principal carer can invite people.",
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      if (isPrincipal &&
                          dataId != null &&
                          dataId.isNotEmpty &&
                          inviteCgId != null &&
                          inviteCgId.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: _AddPeopleToCareTeamCard(
                            dataCareGroupId: dataId,
                            inviteCareGroupId: inviteCgId,
                          ),
                        ),
                    ],
                  );
                }
                if (state is MembersDisplay) {
                  return BlocBuilder<AuthBloc, AuthState>(
                    buildWhen: (p, c) => p.user?.uid != c.user?.uid,
                    builder: (context, auth) {
                      final selfUid = auth.user?.uid;
                      return BlocBuilder<ProfileCubit, ProfileState>(
                        buildWhen: (p, c) {
                          if (p is! ProfileReady && c is! ProfileReady) {
                            return false;
                          }
                          if (p is ProfileReady && c is ProfileReady) {
                            return p.profile.uid != c.profile.uid ||
                                p.profile.photoUrl != c.profile.photoUrl ||
                                p.profile.avatarIndex != c.profile.avatarIndex;
                          }
                          return true;
                        },
                        builder: (context, profileState) {
                          final selfProfile = profileState is ProfileReady
                              ? profileState.profile
                              : null;
                          CareGroupMember? me;
                          if (selfUid != null) {
                            for (final x in state.list) {
                              if (x.userId == selfUid) {
                                me = x;
                                break;
                              }
                            }
                          }
                          final canEditRoles = me != null &&
                              me.roles.contains("principal_carer");
                          final careGroupId =
                              context.read<MembersCubit>().careGroupId;
                          final canAdd = isPrincipal &&
                              dataId != null &&
                              dataId.isNotEmpty &&
                              inviteCgId != null &&
                              inviteCgId.isNotEmpty;
                          final canUseDelete = isPrincipal &&
                              dataId != null &&
                              dataId.isNotEmpty;
                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              for (var i = 0; i < state.list.length; i++) ...[
                                if (i > 0) const SizedBox(height: 6),
                                _MemberTile(
                                  member: state.list[i],
                                  highlight: selfUid != null &&
                                      state.list[i].userId == selfUid,
                                  careGroupId: careGroupId,
                                  canEditRoles: canEditRoles &&
                                      !state.list[i].isOfflineOnly,
                                  canDelete: canUseDelete &&
                                      (selfUid == null ||
                                          state.list[i].userId != selfUid),
                                  dataCareGroupId: dataId ?? "",
                                  selfProfile: selfUid != null &&
                                          state.list[i].userId == selfUid
                                      ? selfProfile
                                      : null,
                                  authUser: auth.user,
                                ),
                              ],
                              if (canAdd) ...[
                                const SizedBox(height: 12),
                                _AddPeopleToCareTeamCard(
                                  dataCareGroupId: dataId,
                                  inviteCareGroupId: inviteCgId,
                                ),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            );
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
    required this.careGroupId,
    required this.canEditRoles,
    required this.canDelete,
    required this.dataCareGroupId,
    required this.selfProfile,
    required this.authUser,
  });

  final CareGroupMember member;
  final bool highlight;
  final String careGroupId;
  final bool canEditRoles;
  final bool canDelete;
  final String dataCareGroupId;
  final UserProfile? selfProfile;
  final User? authUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromRoster = UserProfile(
      uid: member.userId,
      email: "",
      displayName: member.displayName,
      photoUrl: member.photoUrl,
      avatarIndex: member.avatarIndex,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                member.displayName,
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (highlight)
              Text(
                "You",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.tealPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
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
        if (member.isOfflineOnly) ...[
          const SizedBox(height: 4),
          Text(
            "Not using CareShare — the team can still coordinate care for them here.",
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.grey500,
            ),
          ),
        ],
      ],
    );
    return Card(
      color: highlight ? AppColors.tealLight.withValues(alpha: 0.4) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CareUserAvatar(
              radius: 22,
              user: highlight ? authUser : null,
              profile: highlight && selfProfile != null ? selfProfile! : fromRoster,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: canEditRoles
                  ? Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          unawaited(
                            _EditMemberRolesSheet.show(
                              context,
                              careGroupId: careGroupId,
                              member: member,
                            ),
                          );
                        },
                        child: body,
                      ),
                    )
                  : body,
            ),
            if (canEditRoles) ...[
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  unawaited(
                    _EditMemberRolesSheet.show(
                      context,
                      careGroupId: careGroupId,
                      member: member,
                    ),
                  );
                },
                icon: Icon(
                  Icons.edit_outlined,
                  color: theme.colorScheme.primary,
                ),
                tooltip: "Edit roles",
              ),
            ],
            if (canDelete)
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  unawaited(
                    _confirmAndRemoveRosterEntry(
                      context,
                      member: member,
                      membersCareGroupId: careGroupId,
                      dataCareGroupId: dataCareGroupId,
                    ),
                  );
                },
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.error,
                tooltip: "Remove from this care team",
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmAndRemoveRosterEntry(
  BuildContext context, {
  required CareGroupMember member,
  required String membersCareGroupId,
  required String dataCareGroupId,
}) async {
  if (dataCareGroupId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Missing home id for this care group. Try opening care group settings, then return here.",
          ),
        ),
      );
    }
    return;
  }
  final mRepo = context.read<MembersRepository>();
  final uRepo = context.read<UserRepository>();
  late final MemberDeletionBlockers check;
  try {
    check = await mRepo.getDeletionBlockers(
      dataCareGroupId: dataCareGroupId,
      entityId: member.userId,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Could not check whether it is safe to remove: $e",
          ),
        ),
      );
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  if (!check.canDelete) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          check.reasonIfBlocked ?? "This person is still linked to data in this home.",
        ),
      ),
    );
    return;
  }
  final t = member.displayName.trim().isNotEmpty
      ? member.displayName.trim()
      : "this person";
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text("Remove from care team?"),
        content: Text(
          member.isOfflineOnly
              ? "Remove $t from this home. They are not a signed-in user — only their name will be taken off the list."
              : "Remove $t from this care team. They will lose access to this home unless invited again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Remove"),
          ),
        ],
      );
    },
  );
  if (go != true || !context.mounted) {
    return;
  }
  final ms = ScaffoldMessenger.of(context);
  try {
    if (member.isOfflineOnly) {
      await uRepo.removeOfflineCareRecipient(
        dataCareGroupDocId: dataCareGroupId,
        recipientId: member.userId,
      );
    } else {
      await mRepo.deleteMemberDocument(
        careGroupId: membersCareGroupId,
        userId: member.userId,
      );
    }
    if (context.mounted) {
      ms.showSnackBar(
        const SnackBar(content: Text("Removed from this care team.")),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ms.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _EditMemberRolesSheet extends StatefulWidget {
  const _EditMemberRolesSheet({
    required this.careGroupId,
    required this.member,
  });

  final String careGroupId;
  final CareGroupMember member;

  static Future<void> show(
    BuildContext context, {
    required String careGroupId,
    required CareGroupMember member,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _EditMemberRolesSheet(
        careGroupId: careGroupId,
        member: member,
      ),
    );
  }

  @override
  State<_EditMemberRolesSheet> createState() => _EditMemberRolesSheetState();
}

class _EditMemberRolesSheetState extends State<_EditMemberRolesSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.member.roles};
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Choose at least one role."),
        ),
      );
      return;
    }
    final repo = context.read<MembersRepository>();
    try {
      await repo.updateMemberRoles(
        careGroupId: widget.careGroupId,
        userId: widget.member.userId,
        roles: _selected.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.member.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            "A person can have more than one role in this care team.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kAssignableCareGroupRoles.map((id) {
              final on = _selected.contains(id);
              return FilterChip(
                label: Text(careGroupRoleLabel(id)),
                selected: on,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selected.add(id);
                    } else {
                      _selected.remove(id);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text("Save roles"),
          ),
        ],
      ),
    );
  }
}

class _AddPeopleToCareTeamCard extends StatelessWidget {
  const _AddPeopleToCareTeamCard({
    required this.dataCareGroupId,
    required this.inviteCareGroupId,
  });

  final String dataCareGroupId;
  final String inviteCareGroupId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Add people to this care team",
              style: t.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              "Invite carers or care recipients by email. If someone will not use CareShare, add them here so the team can still track care for them on their behalf.",
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _showInviteByEmailDialog(
                context,
                careGroupId: inviteCareGroupId,
                dataCareGroupId: dataCareGroupId,
              ),
              icon: const Icon(Icons.outgoing_mail),
              label: const Text("Invite by email"),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showAddOfflineRecipientDialog(
                context,
                dataCareGroupId: dataCareGroupId,
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text("Add someone who won’t use the app"),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showInviteByEmailDialog(
  BuildContext context, {
  required String careGroupId,
  required String dataCareGroupId,
}) async {
  final email = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text("Invite by email"),
        content: TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: "Email address",
            hintText: "name@example.com",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Send invite"),
          ),
        ],
      );
    },
  );
  if (ok != true || !context.mounted) {
    email.dispose();
    return;
  }
  final repo = context.read<InvitationRepository>();
  final ms = ScaffoldMessenger.of(context);
  try {
    await repo.createInvitation(
      careGroupId: careGroupId,
      dataCareGroupId: dataCareGroupId,
      email: email.text,
    );
    if (context.mounted) {
      ms.showSnackBar(
        const SnackBar(content: Text("Invitation created.")),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ms.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  } finally {
    email.dispose();
  }
}

Future<void> _showAddOfflineRecipientDialog(
  BuildContext context, {
  required String dataCareGroupId,
}) async {
  final name = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text("Add without the app"),
        content: TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: "Name",
            hintText: "How they should appear in this home",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Add"),
          ),
        ],
      );
    },
  );
  if (ok != true || !context.mounted) {
    name.dispose();
    return;
  }
  final ur = context.read<UserRepository>();
  final ms = ScaffoldMessenger.of(context);
  try {
    await ur.addOfflineCareRecipient(
      dataCareGroupDocId: dataCareGroupId,
      displayName: name.text,
    );
    if (context.mounted) {
      ms.showSnackBar(
        const SnackBar(content: Text("Added to this home.")),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ms.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  } finally {
    name.dispose();
  }
}
