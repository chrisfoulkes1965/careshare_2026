import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/channels_cubit.dart";
import "../cubit/channels_state.dart";
import "../repository/chat_repository.dart";
import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "create_channel_sheet.dart";

class ChatChannelsScreen extends StatelessWidget {
  const ChatChannelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final dataCg = state.activeCareGroupDataId;
        if (dataCg == null || dataCg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Chat")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to use chat. Complete setup or join a care group first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final membersCg =
            state.activeCareGroupMemberDocId ?? dataCg;
        return BlocProvider(
          key: ObjectKey("channels_$dataCg"),
          create: (context) => ChannelsCubit(
            repository: context.read<ChatRepository>(),
            careGroupId: dataCg,
          )..subscribe(),
          child: _ChannelsScaffold(
            careGroupId: dataCg,
            memberListCareGroupId: membersCg,
          ),
        );
      },
    );
  }
}

class _ChannelsScaffold extends StatelessWidget {
  const _ChannelsScaffold({
    required this.careGroupId,
    required this.memberListCareGroupId,
  });

  final String careGroupId;
  final String memberListCareGroupId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChannelsCubit, ChannelsState>(
      listener: (context, state) {
        if (state is ChannelsFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Chat"),
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
          body: _ChannelsBody(
            state: state,
            careGroupId: careGroupId,
          ),
          floatingActionButton: _CreateChannelFab(
            careGroupId: careGroupId,
            memberListCareGroupId: memberListCareGroupId,
          ),
        );
      },
    );
  }
}

class _CreateChannelFab extends StatelessWidget {
  const _CreateChannelFab({
    required this.careGroupId,
    required this.memberListCareGroupId,
  });

  final String careGroupId;
  final String memberListCareGroupId;

  @override
  Widget build(BuildContext context) {
    final mem = context.read<MembersRepository>();
    if (!mem.isAvailable) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<CareGroupMember>>(
      stream: mem.watchMembers(memberListCareGroupId),
      builder: (context, snap) {
        final u = context.read<AuthBloc>().state.user?.uid;
        if (u == null || !snap.hasData) {
          return const SizedBox.shrink();
        }
        CareGroupMember? me;
        for (final m in snap.data!) {
          if (m.userId == u) {
            me = m;
            break;
          }
        }
        if (me == null) {
          return const SizedBox.shrink();
        }
        final ok = me.hasCarerOrOrganiserChatAccess;
        if (!ok) {
          return const SizedBox.shrink();
        }
        return FloatingActionButton(
          onPressed: () => CreateChannelSheet.show(
            context,
            careGroupId: careGroupId,
            memberListCareGroupId: memberListCareGroupId,
          ),
          child: const Icon(Icons.add),
        );
      },
    );
  }
}

class _ChannelsBody extends StatelessWidget {
  const _ChannelsBody({required this.state, required this.careGroupId});

  final ChannelsState state;
  final String careGroupId;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s is ChannelsInitial || s is ChannelsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s is ChannelsFailure) {
      return Center(
        child: Text(s.message, textAlign: TextAlign.center),
      );
    }
    if (s is! ChannelsDisplay) {
      return const SizedBox.shrink();
    }
    final rows = s.rows;
    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<ChannelsCubit>().refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                "No channels yet. Carers and principal carers can create a topic and choose who is in it.",
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<ChannelsCubit>().refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final r = rows[i];
          return Card(
            child: ListTile(
              leading: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.tealPrimary,
              ),
              title: Text(r.channel.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    [
                      "Topic: ${r.channel.topic}",
                      if (r.channel.description.isNotEmpty)
                        r.channel.description,
                    ].join(" · "),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (r.channel.whatsappInviteUrl != null &&
                      r.channel.whatsappInviteUrl!.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        "Also linked to a WhatsApp group (open from chat)",
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF25D366),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              isThreeLine: r.channel.description.length > 40 ||
                  (r.channel.whatsappInviteUrl != null &&
                      r.channel.whatsappInviteUrl!.isNotEmpty),
              trailing: r.unread > 0 ? _UnreadBadge(n: r.unread) : null,
              onTap: () async {
                await context.push("/chat/${r.channel.id}");
                if (context.mounted) {
                  await context.read<ChannelsCubit>().refresh();
                }
              },
            ),
          );
        },
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.n});

  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tealPrimary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        n > 99 ? "99+" : "$n",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
