import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/care/role_label.dart";
import "../../settings/repository/group_calendar_service.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../calendar/models/linked_calendar_event.dart";
import "../../calendar/repository/linked_calendar_events_repository.dart";
import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../cubit/invitations_cubit.dart";
import "../cubit/invitations_state.dart";
import "../models/care_invitation.dart";
import "../repository/invitation_repository.dart";
import "../utils/calendar_invitee_suggestions.dart";
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
                dataCareGroupId: cg,
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

class _InvitationsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
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
    required this.dataCareGroupId,
    required this.canManage,
    required this.showInviteFab,
  });

  final String dataCareGroupId;
  final bool canManage;
  final bool showInviteFab;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<LinkedCalendarEventsRepository>();

    return Scaffold(
      appBar: const _InvitationsAppBar(),
      body: SafeArea(
        child: StreamBuilder<bool>(
          stream: context
              .read<GroupCalendarService>()
              .watchResolvedInboundCalendarForDataDoc(dataCareGroupId),
          builder: (context, gate) {
            final mirrorAllowed = !gate.hasError && (gate.data ?? false);
            return StreamBuilder<List<LinkedCalendarEvent>>(
              stream: repo.isAvailable && mirrorAllowed
                  ? repo.watchLinkedEvents(dataCareGroupId)
                  : Stream<List<LinkedCalendarEvent>>.value(
                      const <LinkedCalendarEvent>[],
                    ),
              builder: (context, calSnap) {
                final events = calSnap.data ?? const <LinkedCalendarEvent>[];
                return BlocConsumer<InvitationsCubit, InvitationsState>(
                  listener: (context, state) {
                    if (state is InvitationsFailure) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(state.message)),
                      );
                    }
                  },
                  builder: (context, state) {
                    if (state is InvitationsInitial ||
                        state is InvitationsLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is InvitationsFailure) {
                      return Center(child: Text(state.message));
                    }

                    final invList = state is InvitationsDisplay
                        ? state.list
                        : <CareInvitation>[];
                    final me = context
                        .read<AuthBloc>()
                        .state
                        .user
                        ?.email
                        ?.toLowerCase();
                    final suggestions = mergedCalendarInviteeSuggestions(
                      events: events,
                      invitations: invList,
                      currentUserEmailNormalized: me,
                    );

                    if (invList.isEmpty && suggestions.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.event_available_outlined,
                                size: 48,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "No invitations yet. Connect a group calendar "
                                "(Care group settings) so event participants can appear here, "
                                "or use + to invite by email.",
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (suggestions.isNotEmpty) ...[
                          Text(
                            "From imported calendar",
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Organizers and guests on synced events (excluding people already on "
                            "pending or accepted invitations, and your own address).",
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: 10),
                          ...suggestions.map(
                            (s) => Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                leading:
                                    const Icon(Icons.calendar_month_outlined),
                                title: Text(s.titleLine),
                                subtitle: Text(
                                  s.sampleEventTitle != null
                                      ? "${s.emailNormalized}\n${s.sampleEventTitle}"
                                      : s.emailNormalized,
                                ),
                                isThreeLine: s.sampleEventTitle != null,
                                trailing: canManage
                                    ? TextButton(
                                        onPressed: () => _invite(
                                          context,
                                          initialEmail: s.emailNormalized,
                                        ),
                                        child: const Text("Invite"),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          if (invList.isNotEmpty) const SizedBox(height: 14),
                        ],
                        if (invList.isNotEmpty) ...[
                          Text(
                            suggestions.isEmpty
                                ? "Invitations"
                                : "Invitation emails",
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          ...invList.asMap().entries.map((e) {
                            final i = e.key;
                            final inv = e.value;
                            final pending = inv.status == "pending";
                            final roleLine = inv.invitedRoles
                                .map(careGroupRoleLabel)
                                .join(", ");
                            return Padding(
                              padding: EdgeInsets.only(
                                  bottom: i == invList.length - 1 ? 0 : 6),
                              child: Card(
                                child: ListTile(
                                  title: Text(inv.invitedEmail),
                                  subtitle: Text(
                                    "Roles: $roleLine\n"
                                    "${inv.inviteOnboardingSubtitle}\n"
                                    "Invitation: ${inv.status}\n${inv.emailStatusLine}",
                                  ),
                                  isThreeLine: true,
                                  leading: const Icon(Icons.mail_outline),
                                  trailing: canManage && pending
                                      ? PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert),
                                          onSelected: (value) =>
                                              _onInviteAction(
                                            context,
                                            value,
                                            inv.id,
                                          ),
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: "resend",
                                              child: Row(
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .forward_to_inbox_outlined,
                                                      size: 20),
                                                  SizedBox(width: 8),
                                                  Text("Resend email"),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: "rescind",
                                              child: Row(
                                                children: [
                                                  Icon(Icons.link_off_outlined,
                                                      size: 20),
                                                  SizedBox(width: 8),
                                                  Text("Rescind invitation"),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    );
                  },
                );
              },
            );
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
        await context
            .read<InvitationsCubit>()
            .resendInvitationEmail(invitationId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Resend requested. The invite status below should update in a few seconds.",
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

  Future<void> _invite(BuildContext context, {String? initialEmail}) async {
    final result =
        await showInviteEmailRolesDialog(context, initialEmail: initialEmail);
    if (result == null || !context.mounted) return;
    try {
      await context.read<InvitationsCubit>().invite(result.email, result.roles);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Invitation saved. They’ll receive an email with a link when automated "
              "invite email is enabled for your team.",
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
