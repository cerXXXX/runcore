import 'dart:async';

import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../../core/platform/runcore_channel.dart';
import '../data/chat_repository.dart';

class ChatController {
  ChatController({
    required ChatRepository repository,
    required RuncorePaths paths,
    required String destHashHex,
  }) : _repository = repository,
       _paths = paths,
       _destHashHex = destHashHex.trim().toLowerCase(),
       _peer = User(
         id: destHashHex.trim().toLowerCase(),
         name: destHashHex.trim().toLowerCase(),
       ),
       chatController = InMemoryChatController(messages: const []);

  final ChatRepository _repository;
  final InMemoryChatController chatController;

  final User me = const User(id: ChatRepository.meId, name: 'Я');
  User _peer;
  RuncorePaths _paths;
  String _destHashHex;
  String _query = '';
  String _signature = '';
  Timer? _poller;

  User get peer => _peer;
  String get destHashHex => _destHashHex;

  void start() {
    _reload();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) => _reload());
  }

  Future<void> update({
    required RuncorePaths paths,
    required String destHashHex,
    required String query,
  }) async {
    final normalizedDest = destHashHex.trim().toLowerCase();
    final normalizedQuery = query.trim();
    final changedDest = normalizedDest != _destHashHex;
    final changedQuery = normalizedQuery != _query;
    _paths = paths;
    _query = normalizedQuery;
    if (changedDest) {
      _destHashHex = normalizedDest;
      _peer = User(id: normalizedDest, name: normalizedDest);
      _signature = '';
      await chatController.setMessages(const [], animated: false);
    }
    if (changedDest || changedQuery) {
      await _reload();
    }
  }

  void dispose() {
    _poller?.cancel();
    chatController.dispose();
  }

  Future<void> sendText(String text) async {
    await _repository.sendText(
      paths: _paths,
      destHashHex: _destHashHex,
      text: text,
    );
    await _reload();
  }

  Future<User?> resolveUser(String id) async {
    if (id == me.id) {
      return me;
    }
    if (id == _peer.id) {
      return _peer;
    }
    return User(id: id, name: id);
  }

  Future<void> _reload() async {
    final next = await _repository.loadMessages(
      paths: _paths,
      destHashHex: _destHashHex,
      query: _query,
      peerId: _peer.id,
    );
    final signature = _buildSignature(next);
    if (signature == _signature) {
      return;
    }
    _signature = signature;
    await chatController.setMessages(next, animated: false);
  }

  String _buildSignature(List<Message> messages) {
    final parts = <String>[];
    for (final message in messages) {
      final buffer = StringBuffer()
        ..write(message.id)
        ..write('|')
        ..write(message.authorId)
        ..write('|')
        ..write(message.createdAt?.millisecondsSinceEpoch ?? 0)
        ..write('|')
        ..write(message.status?.name ?? '');
      if (message is TextMessage) {
        buffer
          ..write('|t|')
          ..write(message.text);
      } else if (message is FileMessage) {
        buffer
          ..write('|f|')
          ..write(message.name)
          ..write('|')
          ..write(message.size ?? 0)
          ..write('|')
          ..write(message.source);
      }
      parts.add(buffer.toString());
    }
    return parts.join('\n');
  }
}
