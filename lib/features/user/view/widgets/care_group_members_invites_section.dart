import "package:firebase_auth/firebase_auth.dart" show User;
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../../core/care/role_label.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../auth/bloc/auth_bloc.dart";
import "../../../auth/bloc/auth_state.dart";
import "../../../care_group/models/care_group_option.dart";
import "../../../invitations/models/care_invitation.dart";
import "../../../invitations/repository/invitation_repository.dart";
import "../../../members/models/care_group_member.dart";
import "../../../members/repository/members_repository.dart";
import "../../../profile/cubit/profile_cubit.dart";
import "../../../profile/cubit/profile_state.dart";
import "../../models/user_profile.dart";
import "care_user_avatar.dart";

/// Home care group settings: preview of members + pending invites, with links to full screens.
class CareGroupMembersInvitesSection extends StatelessWidget {
  const CareGroupMembersInvitesSection({super.key, required this.option});

  final CareGroupOption option;

  static const int _maxMemberPreview = 6;
  static const int _maxInvitePreview = 4;

  @override
  Widget build(BuildContext context) {
    final membersRepo = context.read<MembersRepository>();
    final invitesRepo = context.read<InvitationRepository>();
    final t = Theme.of(context);
    final cg = option.careGroupId;

    if (!membersRepo.isAvailable || !invitesRepo.isAvailable) {
      return Text(
        "Members and invitations load when the app is connected.",
        style: t.textTheme.bodySmall?.copyWith(
          color: t.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "People in this care team and invitations you’ve sent. Open a screen below to change roles, send invites, or add someone who won’t use the app.",
          style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "In this care team",
          style: t.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<CareGroupMember>>(
          stream: membersRepo.watchRoster(cg, option.dataCareGroupId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final all = List<CareGroupMember>.from(snap.data ?? const []);
            if (all.isEmpty) {
              return Text(
                "No signed-in members yet. Use manage below to invite carers or care recipients.",
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              );
            }
            final show = all.length > _maxMemberPreview
                ? all.sublist(0, _maxMemberPreview)
                : all;
            final more = all.length - show.length;
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
                  builder: (context, ps) {
                    final myProfile =
                        ps is ProfileReady ? ps.profile : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final m in show)
                          _SettingsMemberRow(
                            member: m,
                            isSelf: selfUid != null && m.userId == selfUid,
                            authUser: auth.user,
                            myProfile: myProfile,
                          ),
                        if (more > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              "and $more more",
                              style: t.textTheme.labelSmall?.copyWith(
                                color: AppColors.grey500,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              if (context.mounted) context.push("/members");
            },
            icon: const Icon(Icons.manage_accounts_outlined, size: 20),
            label: const Text("Manage members"),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text(
          "Open invitations",
          style: t.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<CareInvitation>>(
          stream: invitesRepo.watchByCareGroup(cg),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final list = snap.data ?? const <CareInvitation>[];
            final open = list
                .where((i) => i.status.toLowerCase() == "pending")
                .toList();
            if (open.isEmpty) {
              return Text(
                "No pending invites. Send one from manage invitations (principal carer).",
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              );
            }
            final show = open.length > _maxInvitePreview
                ? open.sublist(0, _maxInvitePreview)
                : open;
            final more = open.length - show.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final inv in show)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.outgoing_mail,
                          size: 20,
                          color: t.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inv.invitedEmail,
                                style: t.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "Pending",
                                style: t.textTheme.labelSmall?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (more > 0)
                  Text(
                    "and $more more pending",
                    style: t.textTheme.labelSmall?.copyWith(
                      color: AppColors.grey500,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              if (context.mounted) context.push("/invitations");
            },
            icon: const Icon(Icons.forward_to_inbox_outlined, size: 20),
            label: const Text("Manage invitations"),
          ),
        ),
      ],
    );
  }
}

class _SettingsMemberRow extends StatelessWidget {
  const _SettingsMemberRow({
    required this.member,
    required this.isSelf,
    required this.authUser,
    this.myProfile,
  });

  final CareGroupMember member;
  final bool isSelf;
  final User? authUser;
  final UserProfile? myProfile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fromRoster = UserProfile(
      uid: member.userId,
      email: "",
      displayName: member.displayName,
      photoUrl: member.photoUrl,
      avatarIndex: member.avatarIndex,
    );
    final p = (isSelf &&
            myProfile != null &&
            myProfile!.uid == member.userId)
        ? myProfile!
        : fromRoster;
    final roles = member.roles
        .map(careGroupRoleLabel)
        .where((s) => s.isNotEmpty)
        .join(" · ");
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CareUserAvatar(
            radius: 18,
            user: isSelf ? authUser : null,
            profile: p,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.displayName,
                        style: t.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Text(
                        "You",
                        style: t.textTheme.labelSmall?.copyWith(
                          color: AppColors.tealPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (roles.isNotEmpty)
                  Text(
                    roles,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
