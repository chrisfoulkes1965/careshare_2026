import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../cubit/channels_cubit.dart";
import "../repository/chat_repository.dart";

class CreateChannelSheet extends StatefulWidget {
  const CreateChannelSheet({
    super.key,
    required this.careGroupId,
    required this.currentUserUid,
    this.memberListCareGroupId,
  });

  /// `careGroups/{id}/chatChannels`
  final String careGroupId;

  /// Signed-in user's Firebase uid (from [ChannelsCubit] / session).
  final String currentUserUid;

  /// `careGroups/{id}/members` for the roster; defaults to [careGroupId].
  final String? memberListCareGroupId;

  static Future<void> show(
    BuildContext context, {
    required String careGroupId,
    String? memberListCareGroupId,
  }) {
    final channels = context.read<ChannelsCubit>();
    final chatRepo = context.read<ChatRepository>();
    final memRepo = context.read<MembersRepository>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => RepositoryProvider<ChatRepository>.value(
        value: chatRepo,
        child: RepositoryProvider<MembersRepository>.value(
          value: memRepo,
          child: BlocProvider<ChannelsCubit>.value(
            value: channels,
            child: CreateChannelSheet(
              careGroupId: careGroupId,
              currentUserUid: channels.uid,
              memberListCareGroupId: memberListCareGroupId,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<CreateChannelSheet> createState() => _CreateChannelSheetState();
}

class _CreateChannelSheetState extends State<CreateChannelSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _topic = "general";
  final Map<String, bool> _uidSelected = {};
  bool _selectionInitialized = false;
  bool _saving = false;
  String? _error;
  static const _topics = ["general", "medical", "rota", "other"];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _initSelectionOnce(List<CareGroupMember> members) {
    final my = widget.currentUserUid.trim();
    if (my.isEmpty) {
      return;
    }
    if (_selectionInitialized) {
      return;
    }
    _selectionInitialized = true;
    for (final m in members) {
      _uidSelected[m.userId] = m.userId == my;
    }
  }

  List<String> _selectedUids() {
    return _uidSelected.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = "Add a channel name.");
      return;
    }
    final uids = _selectedUids();
    if (uids.isEmpty) {
      setState(() => _error = "Select at least one member (including you).");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = context.read<ChatRepository>();
    final cubit = context.read<ChannelsCubit>();
    try {
      await repo.createChannel(
        careGroupId: widget.careGroupId,
        name: _name.text,
        description: _desc.text,
        topic: _topic,
        memberUids: uids,
      );
      if (!mounted) {
        return;
      }
      unawaited(cubit.refresh());
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        shrinkWrap: true,
        children: [
          Text("New channel", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Carers and principal carers can create a topic channel and choose who is in it.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: "Name",
              hintText: "e.g. Rota, Medical updates",
            ),
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(
              labelText: "Description (optional)",
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(_topic),
            initialValue: _topic,
            decoration: const InputDecoration(labelText: "Topic"),
            items: _topics
                .map(
                  (t) => DropdownMenuItem(value: t, child: Text(t)),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (v) {
                    if (v != null) {
                      setState(() => _topic = v);
                    }
                  },
          ),
          const SizedBox(height: 12),
          Text("Members in this channel",
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          StreamBuilder<List<CareGroupMember>>(
            stream: context.read<MembersRepository>().isAvailable
                ? context
                    .read<MembersRepository>()
                    .watchMembers(
                      widget.memberListCareGroupId ?? widget.careGroupId,
                    )
                : const Stream.empty(),
            builder: (context, snap) {
              if (!context.read<MembersRepository>().isAvailable) {
                return const Text("Could not load members.");
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final members = snap.data!
                ..sort(
                  (a, b) => a.displayName.toLowerCase().compareTo(
                        b.displayName.toLowerCase(),
                      ),
                );
              if (members.isEmpty) {
                return const Text("No members in this care group.");
              }
              if (!_selectionInitialized) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _initSelectionOnce(members);
                    });
                  }
                });
              }
              return Column(
                children: [
                  for (final m in members)
                    CheckboxListTile(
                      value: _uidSelected[m.userId] ?? false,
                      onChanged: _saving
                          ? null
                          : (v) {
                              setState(() {
                                _uidSelected[m.userId] = v ?? false;
                              });
                            },
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(m.displayName),
                    ),
                ],
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Create"),
          ),
        ],
      ),
    );
  }
}
