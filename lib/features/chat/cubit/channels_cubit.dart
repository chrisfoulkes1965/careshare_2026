import "dart:async";

import "package:flutter_bloc/flutter_bloc.dart";

import "../models/chat_channel.dart";
import "../repository/chat_repository.dart";
import "channels_state.dart";

final class ChannelsCubit extends Cubit<ChannelsState> {
  ChannelsCubit({
    required ChatRepository repository,
    required this.careGroupId,
    required this.membersCareGroupId,
    required this.uid,
  })  : _repository = repository,
        super(const ChannelsInitial());

  final ChatRepository _repository;
  final String careGroupId;

  /// Host doc id for [members] (may differ from [careGroupId] when team/data docs are linked).
  final String membersCareGroupId;
  final String uid;

  StreamSubscription<List<ChatChannel>>? _sub;
  int _unreadGen = 0;

  void subscribe() {
    if (!_repository.isAvailable) {
      emit(const ChannelsFailure("Firebase is not available."));
      return;
    }
    emit(const ChannelsLoading());
    unawaited(
      _repository.ensureDefaultGeneralChannel(
        dataCareGroupId: careGroupId,
        membersCareGroupId: membersCareGroupId,
      ),
    );
    unawaited(_sub?.cancel());
    _sub = _repository
        .watchMyChannels(
          careGroupId,
          myUid: uid,
        )
        .listen(
          (list) => _onChannelList(list, uid),
          onError: (Object e) => emit(ChannelsFailure(e.toString())),
        );
  }

  Future<void> _onChannelList(List<ChatChannel> list, String uid) async {
    if (isClosed) {
      return;
    }
    if (list.isEmpty) {
      emit(const ChannelsDisplay(rows: []));
      return;
    }
    final gen = ++_unreadGen;
    final rows = <ChatChannelRow>[];
    for (final c in list) {
      if (isClosed) {
        return;
      }
      if (gen != _unreadGen) {
        return;
      }
      DateTime? lastRead;
      try {
        lastRead = await _repository.getLastRead(
          careGroupId,
          myUid: uid,
          channelId: c.id,
        );
      } catch (_) {
        lastRead = null;
      }
      if (isClosed) {
        return;
      }
      if (gen != _unreadGen) {
        return;
      }
      int unread = 0;
      try {
        unread = await _repository.countUnread(
          careGroupId,
          c.id,
          myUid: uid,
          lastRead: lastRead,
        );
      } catch (_) {
        unread = 0;
      }
      rows.add(ChatChannelRow(channel: c, unread: unread));
    }
    if (isClosed) {
      return;
    }
    if (gen != _unreadGen) {
      return;
    }
    emit(ChannelsDisplay(rows: rows));
  }

  /// Recomputes last-read and unread for the current channel list (e.g. after returning from a thread).
  Future<void> refresh() async {
    final s = state;
    if (s is! ChannelsDisplay) {
      return;
    }
    await _onChannelList(
      s.rows.map((r) => r.channel).toList(),
      uid,
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
