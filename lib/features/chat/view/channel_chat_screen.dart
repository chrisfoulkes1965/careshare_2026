import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";
import "package:url_launcher/url_launcher.dart";

import "../../../core/theme/app_colors.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../models/chat_message.dart";
import "../repository/chat_repository.dart";
import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";

bool _canManageWhatsappLink(List<CareGroupMember>? members, String? myUid) {
  if (members == null || myUid == null) {
    return false;
  }
  for (final m in members) {
    if (m.userId == myUid) {
      return m.roles.contains("principal_carer") || m.roles.contains("carer");
    }
  }
  return false;
}

bool _isValidWhatsappGroupInvite(String s) {
  final t = s.trim();
  return t.isEmpty || t.toLowerCase().startsWith("https://chat.whatsapp.com/");
}

Future<void> _openWhatsappGroupInviteInBrowser(String url) async {
  final uri = Uri.parse(url.trim());
  if (!await canLaunchUrl(uri)) {
    return;
  }
  await launchUrl(
    uri,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
  );
}

Future<void> _showWhatsappGroupLinkDialog({
  required BuildContext context,
  required String careGroupId,
  required String channelId,
  String? currentUrl,
}) async {
  final c = TextEditingController(text: currentUrl ?? "");
  final r = context.read<ChatRepository>();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("WhatsApp group link"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Paste a group invite from WhatsApp (Group info → Invite to group via link). "
            "This does not copy messages in either direction — it is a quick way to open the same people in WhatsApp.",
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: "https://chat.whatsapp.com/…",
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () {
            if (!_isValidWhatsappGroupInvite(c.text)) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Use an invite link that starts with https://chat.whatsapp.com/ or leave empty.",
                  ),
                ),
              );
              return;
            }
            Navigator.of(ctx).pop(true);
          },
          child: const Text("Save"),
        ),
      ],
    ),
  );
  if (go != true) {
    c.dispose();
    return;
  }
  if (!context.mounted) {
    c.dispose();
    return;
  }
  try {
    final t = c.text.trim();
    await r.setChannelWhatsappInviteUrl(
      careGroupId,
      channelId: channelId,
      whatsappInviteUrl: t.isEmpty ? null : t,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
  c.dispose();
}

class ChannelChatScreen extends StatefulWidget {
  const ChannelChatScreen({
    super.key,
    required this.channelId,
    this.careGroupIdFromRoute,
  });

  final String channelId;

  /// When opened from a push, matches the [careGroupId] the channel lives under.
  final String? careGroupIdFromRoute;

  @override
  State<ChannelChatScreen> createState() => _ChannelChatScreenState();
}

class _ChannelChatScreenState extends State<ChannelChatScreen> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final p = context.read<ProfileCubit>().state;
      if (p is! ProfileReady) {
        return;
      }
      final cg = p.activeCareGroupDataId;
      if (cg == null || cg.isEmpty) {
        return;
      }
      final u = FirebaseAuth.instance.currentUser?.uid;
      if (u == null) {
        return;
      }
      unawaited(
        context.read<ChatRepository>().markRead(
              cg,
              myUid: u,
              channelId: widget.channelId,
            ),
      );
    });
  }

  Future<void> _send() async {
    if (_sending) {
      return;
    }
    final t = _text.text.trim();
    if (t.isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final p = context.read<ProfileCubit>().state;
      if (p is! ProfileReady) {
        return;
      }
      final cg = p.activeCareGroupDataId;
      if (cg == null) {
        return;
      }
      await context.read<ChatRepository>().sendTextMessage(
            cg,
            channelId: widget.channelId,
            text: t,
          );
      if (mounted) {
        _text.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _confirmLeave() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Leave this channel?"),
        content: const Text(
          "You will need to be added again to see it later.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Leave"),
          ),
        ],
      ),
    );
    if (go != true || !mounted) {
      return;
    }
    final p = context.read<ProfileCubit>().state;
    if (p is! ProfileReady) {
      return;
    }
    final cg = p.activeCareGroupDataId;
    final u = FirebaseAuth.instance.currentUser?.uid;
    if (cg == null || u == null) {
      return;
    }
    try {
      await context.read<ChatRepository>().leaveChannel(
            cg,
            channelId: widget.channelId,
            myUid: u,
          );
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profileState) {
        if (profileState is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Profile not ready.")),
          );
        }
        final fromRoute = widget.careGroupIdFromRoute;
        final fromProfileData = profileState.activeCareGroupDataId;
        final fromProfileMembers = profileState.activeCareGroupMemberDocId;
        final cg = (fromRoute != null && fromRoute.isNotEmpty)
            ? fromRoute
            : fromProfileData;
        if (cg == null || cg.isEmpty) {
          return const Scaffold(
            body: Center(child: Text("No care group.")),
          );
        }
        final membersDocId = (fromRoute != null && fromRoute.isNotEmpty)
            ? fromRoute
            : (fromProfileMembers ?? cg);
        return _ChatContent(
          careGroupId: cg,
          memberListCareGroupId: membersDocId,
          channelId: widget.channelId,
          textController: _text,
          sending: _sending,
          error: _error,
          onSend: _send,
          onLeave: _confirmLeave,
        );
      },
    );
  }
}

class _ChatContent extends StatelessWidget {
  const _ChatContent({
    required this.careGroupId,
    required this.memberListCareGroupId,
    required this.channelId,
    required this.textController,
    required this.sending,
    required this.error,
    required this.onSend,
    required this.onLeave,
  });

  final String careGroupId;
  final String memberListCareGroupId;
  final String channelId;
  final TextEditingController textController;
  final bool sending;
  final String? error;
  final Future<void> Function() onSend;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    final chRef = FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("chatChannels")
        .doc(channelId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: chRef.snapshots(),
      builder: (context, chSnap) {
        final d = chSnap.data?.data();
        final title = (d != null ? (d["name"] as String?) : null)?.trim();
        final waUrl = d != null
            ? (d["whatsappInviteUrl"] is String
                ? (d["whatsappInviteUrl"] as String).trim()
                : "")
            : "";
        final hasWa = waUrl.isNotEmpty &&
            waUrl.toLowerCase().startsWith("https://chat.whatsapp.com/");
        return StreamBuilder<List<CareGroupMember>>(
          stream: context
              .read<MembersRepository>()
              .watchMembers(memberListCareGroupId),
          builder: (context, memSnap) {
            final myUid = FirebaseAuth.instance.currentUser?.uid;
            final canLink = _canManageWhatsappLink(memSnap.data, myUid);
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  (title == null || title.isEmpty) ? "Channel" : title,
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  if (hasWa)
                    IconButton(
                      tooltip: "Open linked WhatsApp group",
                      icon: const Icon(
                        Icons.chat_rounded,
                        color: Color(0xFF25D366),
                      ),
                      onPressed: () => _openWhatsappGroupInviteInBrowser(waUrl),
                    ),
                  if (canLink)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      tooltip: "Channel options",
                      onSelected: (v) async {
                        if (v == "link") {
                          if (!context.mounted) {
                            return;
                          }
                          await _showWhatsappGroupLinkDialog(
                            context: context,
                            careGroupId: careGroupId,
                            channelId: channelId,
                            currentUrl: hasWa ? waUrl : null,
                          );
                        } else if (v == "clear" && hasWa) {
                          try {
                            await context
                                .read<ChatRepository>()
                                .setChannelWhatsappInviteUrl(
                                  careGroupId,
                                  channelId: channelId,
                                  whatsappInviteUrl: null,
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      "WhatsApp link removed from this channel."),
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
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: "link",
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.link),
                            title: Text("Set WhatsApp group link"),
                          ),
                        ),
                        if (hasWa)
                          const PopupMenuItem(
                            value: "clear",
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.link_off),
                              title: Text("Remove WhatsApp link"),
                            ),
                          ),
                      ],
                    ),
                  TextButton(
                    onPressed: onLeave,
                    child: const Text("Leave"),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (hasWa)
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.5),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "WhatsApp is linked to this channel",
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "CareShare and WhatsApp are separate. Messages you send here stay here; use the button to open the WhatsApp group the team agreed on.",
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _openWhatsappGroupInviteInBrowser(waUrl),
                              child: const Text("Open"),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (canLink && !hasWa)
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.forum_outlined,
                              size: 20,
                              color: Color(0xFF25D366),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Optionally add your team’s WhatsApp group invite so everyone can open it from here.",
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showWhatsappGroupLinkDialog(
                                context: context,
                                careGroupId: careGroupId,
                                channelId: channelId,
                              ),
                              child: const Text("Add link"),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _MessagesPane(
                      careGroupId: careGroupId,
                      memberListCareGroupId: memberListCareGroupId,
                      channelId: channelId,
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  SafeArea(
                    child: Material(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: textController,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: "Message",
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => onSend(),
                              ),
                            ),
                            sending
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton.filled(
                                    onPressed: onSend,
                                    icon: const Icon(Icons.send),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MessagesPane extends StatelessWidget {
  const _MessagesPane({
    required this.careGroupId,
    required this.memberListCareGroupId,
    required this.channelId,
  });

  final String careGroupId;
  final String memberListCareGroupId;
  final String channelId;

  String _nameFor(
    String uid,
    String myUid,
    Map<String, String> names,
  ) {
    if (uid == myUid) {
      return "You";
    }
    return names[uid] ?? "Member";
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final repo = context.read<ChatRepository>();
    if (!repo.isAvailable) {
      return const Center(child: Text("Chat is not available."));
    }
    return StreamBuilder<List<CareGroupMember>>(
      stream: context
          .read<MembersRepository>()
          .watchMembers(memberListCareGroupId),
      builder: (context, nameSnap) {
        final names = {
          for (final m in nameSnap.data ?? <CareGroupMember>[])
            m.userId: m.displayName
        };
        return StreamBuilder<List<ChatMessage>>(
          stream: repo.watchMessages(
            careGroupId,
            channelId,
            limit: 100,
          ),
          builder: (context, msgSnap) {
            if (msgSnap.hasError) {
              return Center(
                child: Text(
                  msgSnap.error.toString(),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (!msgSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = msgSnap.data!;
            if (list.isEmpty) {
              return const Center(
                child: Text(
                  "No messages yet. Say hello.",
                ),
              );
            }
            // Newest at bottom: data is [newest ... oldest] from query.
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              reverse: true,
              itemCount: list.length,
              itemBuilder: (context, i) {
                final m = list[i];
                return _MessageBubble(
                  name: _nameFor(m.createdBy, myUid, names),
                  text: m.text,
                  time: m.createdAt,
                  mine: m.createdBy == myUid,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.name,
    required this.text,
    required this.time,
    required this.mine,
  });

  final String name;
  final String text;
  final DateTime? time;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final t = time == null
        ? ""
        : "${time!.hour.toString().padLeft(2, "0")}:${time!.minute.toString().padLeft(2, "0")}";
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: mine
              ? AppColors.tealLight
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.tealPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (t.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                t,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
