import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../../../core/platform/runcore_channel.dart';
import '../application/chat_controller.dart';
import '../data/chat_repository.dart';

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.paths,
    required this.destHashHex,
    required this.query,
  });

  final RuncorePaths paths;
  final String destHashHex;
  final String query;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChatController(
      repository: ChatRepository(),
      paths: widget.paths,
      destHashHex: widget.destHashHex,
    );
    _controller.start();
    _controller.update(
      paths: widget.paths,
      destHashHex: widget.destHashHex,
      query: widget.query,
    );
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.update(
      paths: widget.paths,
      destHashHex: widget.destHashHex,
      query: widget.query,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Chat(
      currentUserId: _controller.me.id,
      resolveUser: _controller.resolveUser,
      chatController: _controller.chatController,
      onMessageSend: _controller.sendText,
    );
  }
}
