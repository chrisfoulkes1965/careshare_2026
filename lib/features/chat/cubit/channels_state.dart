import "package:equatable/equatable.dart";

import "../models/chat_channel.dart";

sealed class ChannelsState extends Equatable {
  const ChannelsState();
  @override
  List<Object?> get props => [];
}

final class ChannelsInitial extends ChannelsState {
  const ChannelsInitial();
}

final class ChannelsLoading extends ChannelsState {
  const ChannelsLoading();
}

final class ChannelsDisplay extends ChannelsState {
  const ChannelsDisplay({required this.rows});

  final List<ChatChannelRow> rows;

  @override
  List<Object?> get props => [rows];
}

final class ChatChannelRow {
  const ChatChannelRow({required this.channel, required this.unread});

  final ChatChannel channel;
  final int unread;
}

final class ChannelsFailure extends ChannelsState {
  const ChannelsFailure(this.message);

  final String message;
  @override
  List<Object?> get props => [message];
}
