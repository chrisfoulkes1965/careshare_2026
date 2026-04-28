import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/care/role_label.dart";
import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/invitations_cubit.dart";
import "../cubit/invitations_state.dart";
import "../repository/invitation_repository.dart";
import "../widgets/invite_email_roles_dialog.dart";

class InvitationsScreen extends StatelessWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final p = state.profile;
        final cg = state.activeCareGroupDataId;
        if (cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Invitations")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need an active care group to manage invitations. Finish setup or join a care group first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final careGroupId = p.activeCareGroupId ?? cg;
        return StreamBuilder<List<CareGroupMember>>(
          stream: context
              .read<MembersRepository>()
              .watchMembersOrRoster(careGroupId, cg),
          builder: (context, memSnap) {
            if (memSnap.data == null) {
              return const Scaffold(
                appBar: _InvitationsAppBar(),
                body: Center(child: CircularProgressIndicator()),
              );
            }
            CareGroupMember? me;
            for (final m in memSnap.data!) {
              if (m.userId == p.uid) {
                me = m;
                break;
              }
            }
            final canManage = me?.canAssignMemberRoles ?? false;
            return BlocProvider(
              key: ObjectKey(cg),
              create: (context) => InvitationsCubit(
                repository: context.read<InvitationRepository>(),
                careGroupId: careGroupId,
                dataCareGroupId: cg,
              )..subscribe(),
              child: _InvitationsView(
                canManage: canManage,
                showInviteFab: canManage,
              ),
            );
          },
        );
      },
    );
  }
}

class _InvitationsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _InvitationsAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text("Invitations"),
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
    );
  }
}

class _InvitationsView extends StatelessWidget {
  const _InvitationsView({
    required this.canManage,
    required this.showInviteFab,
  });

  final bool canManage;
  final bool showInviteFab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _InvitationsAppBar(),
      body: SafeArea(
        child: BlocConsumer<InvitationsCubit, InvitationsState>(
          listener: (context, state) {
            if (state is InvitationsFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is InvitationsInitial || state is InvitationsLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is InvitationsEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "No pending or past invitations. Invite a carer or family member by email.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (state is InvitationsDisplay) {
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final inv = state.list[i];
                  final pending = inv.status == "pending";
                  final roleLine = inv.invitedRoles
                      .map(careGroupRoleLabel)
                      .join(", ");
                  return Card(
                    child: ListTile(
                      title: Text(inv.invitedEmail),
                      subtitle: Text(
                        "Roles: $roleLine\n"
                        "Invitation: ${inv.status}\n${inv.emailStatusLine}",
                      ),
                      isThreeLine: true,
                      leading: const Icon(Icons.mail_outline),
                      trailing: canManage && pending
                          ? PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) => _onInviteAction(
                                context,
                                value,
                                inv.id,
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: "resend",
                                  child: Row(
                                    children: [
                                      Icon(Icons.forward_to_inbox_outlined, size: 20),
                                      SizedBox(width: 8),
                                      Text("Resend email"),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: "rescind",
                                  child: Row(
                                    children: [
                                      Icon(Icons.link_off_outlined, size: 20),
                                      SizedBox(width: 8),
                                      Text("Rescind invitation"),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              );
            }
            if (state is InvitationsFailure) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: showInviteFab
          ? FloatingActionButton(
              onPressed: () => _invite(context),
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
    );
  }

  Future<void> _onInviteAction(
    BuildContext context,
    String action,
    String invitationId,
  ) async {
    if (action == "rescind") {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Rescind invitation?"),
          content: const Text(
            "They will not be able to use this invite link. You can send a new invitation to the same email if you need to later.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Rescind"),
            ),
          ],
        ),
      );
      if (go != true || !context.mounted) return;
      try {
        await context.read<InvitationsCubit>().rescindInvitation(invitationId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invitation rescinded.")),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
      return;
    }
    if (action == "resend") {
      try {
        await context.read<InvitationsCubit>().resendInvitationEmail(invitationId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Resend requested. Email status will update in a few seconds if Resend is configured.",
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }

  Future<void> _invite(BuildContext context) async {
    final result = await showInviteEmailRolesDialog(context);
    if (result == null || !context.mounted) return;
    try {
      await context.read<InvitationsCubit>().invite(result.email, result.roles);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Invitation saved. The invitee will get an email with a sign-in link if "
              "Resend and a sending address are configured for Cloud Functions.",
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}
