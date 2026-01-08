import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const RuncoreApp());

class RuncoreApp extends StatelessWidget {
  const RuncoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Runcore',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const ChatListPage(),
    );
  }
}

class RuncorePaths {
  const RuncorePaths({
    required this.contactsDir,
    required this.sendDir,
    required this.messagesDir,
    required this.configDir,
  });

  final String contactsDir;
  final String sendDir;
  final String messagesDir;
  final String configDir;

  bool get isValid => contactsDir.isNotEmpty && sendDir.isNotEmpty && messagesDir.isNotEmpty;
}

class RuncoreChannel {
  static const _channel = MethodChannel('runcore');

  static Future<RuncorePaths> getPaths() async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPaths');
    if (res == null) {
      throw StateError('getPaths вернул null');
    }
    return RuncorePaths(
      contactsDir: (res['contactsDir'] as String?) ?? '',
      sendDir: (res['sendDir'] as String?) ?? '',
      messagesDir: (res['messagesDir'] as String?) ?? '',
      configDir: (res['configDir'] as String?) ?? '',
    );
  }
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  RuncorePaths? _paths;
  String? _error;
  final _destController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _destController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _error = null;
    });
    try {
      final p = await RuncoreChannel.getPaths();
      if (!p.isValid) throw StateError('Пути пустые: $p');
      setState(() => _paths = p);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  static bool _isHiddenName(String name) => name.startsWith('.');

  List<String> _listConversationIds(RuncorePaths p) {
    final ids = <String>{};

    void addFromDir(String root) {
      try {
        final d = Directory(root);
        if (!d.existsSync()) return;
        for (final e in d.listSync(followLinks: false)) {
          if (e is! Directory) continue;
          final name = e.path.split(Platform.pathSeparator).last;
          if (_isHiddenName(name)) continue;
          ids.add(name);
        }
      } catch (_) {}
    }

    addFromDir(p.messagesDir);
    addFromDir(p.sendDir);
    addFromDir('${p.sendDir}${Platform.pathSeparator}.pending');

    final out = ids.toList()..sort();
    return out;
  }

  void _openChat(RuncorePaths p, String dest) {
    dest = dest.trim().toLowerCase();
    if (dest.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(paths: p, destHashHex: dest),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _paths;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Runcore'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: p == null
          ? Center(child: Text(_error ?? 'Загрузка…'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _destController,
                          decoration: const InputDecoration(
                            labelText: 'destHashHex',
                            border: OutlineInputBorder(),
                          ),
                          autocorrect: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => _openChat(p, _destController.text),
                        child: const Text('Открыть'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        title: const Text('Пути (debug)'),
                        subtitle: Text(
                          'contacts: ${p.contactsDir}\n'
                          'send: ${p.sendDir}\n'
                          'messages: ${p.messagesDir}\n'
                          'config: ${p.configDir}',
                        ),
                        isThreeLine: true,
                      ),
                      const Divider(height: 1),
                      ..._listConversationIds(p).map(
                        (id) => ListTile(
                          title: Text(id),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openChat(p, id),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.paths, required this.destHashHex});

  final RuncorePaths paths;
  final String destHashHex;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _uuid = Uuid();
  static const _meId = 'me';

  late final User _me;
  late final User _peer;
  late final InMemoryChatController _chatController;
  List<String> _lastMessageIds = const [];

  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _me = const User(id: _meId, name: 'Я');
    _peer = User(id: widget.destHashHex, name: widget.destHashHex);
    _chatController = InMemoryChatController(messages: const []);
    _reload();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) => _reload());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  static final _tsRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2})꞉(\d{2})');

  DateTime _guessCreatedAt(String fileName) {
    final m = _tsRe.firstMatch(fileName);
    if (m != null) {
      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      final h = int.parse(m.group(4)!);
      final mi = int.parse(m.group(5)!);
      return DateTime(y, mo, d, h, mi);
    }

    if (fileName.contains(' -- ')) {
      final parts = fileName.split(' -- ');
      if (parts.length >= 2) {
        final tail = parts.last;
        final num = int.tryParse(tail.split('.').first.trim());
        if (num != null) return DateTime.fromMillisecondsSinceEpoch(num);
      }
    }

    return DateTime.now();
  }

  bool _isOutboundByName(String fileName) {
    // Outbound files come from send folder and keep " -- " marker.
    // Inbound files are strictly "YYYY-MM-DD HH꞉MM(.txt| <name>)" and don't contain " -- ".
    return fileName.contains(' -- ');
  }

  List<File> _listFiles(String dir) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return const [];
      return d
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => !f.path.split(Platform.pathSeparator).last.startsWith('.'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _reload() async {
    final dest = widget.destHashHex;
    final p = widget.paths;

    final deliveredDir = '${p.messagesDir}${Platform.pathSeparator}$dest';
    final sendDir = '${p.sendDir}${Platform.pathSeparator}$dest';
    final pendingDir = '${p.sendDir}${Platform.pathSeparator}.pending${Platform.pathSeparator}$dest';

    final files = <File>[
      ..._listFiles(deliveredDir),
      ..._listFiles(sendDir),
      ..._listFiles(pendingDir),
    ];

    final next = <Message>[];
    for (final f in files) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name.toLowerCase() == 'caption.txt') continue;

      final createdAt = _guessCreatedAt(name);
      final isPending = f.path.startsWith(sendDir) || f.path.startsWith(pendingDir);
      final outbound = _isOutboundByName(name) || isPending;
      final authorId = outbound ? _meId : _peer.id;

      final ext = name.toLowerCase().split('.').last;
      if (ext == 'txt') {
        final text = await f.readAsString().catchError((_) => '');
        next.add(
          Message.text(
            id: f.path,
            authorId: authorId,
            createdAt: createdAt,
            text: text.trim(),
            status: isPending ? MessageStatus.sending : null,
          ),
        );
        continue;
      }

      int? size;
      try {
        size = (await f.stat()).size;
      } catch (_) {}
      next.add(
        Message.file(
          id: f.path,
          authorId: authorId,
          createdAt: createdAt,
          name: name,
          size: size,
          source: f.path,
          status: isPending ? MessageStatus.sending : (outbound ? MessageStatus.sent : null),
        ),
      );
    }

    next.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final c = at.compareTo(bt);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });

    final nextIds = next.map((m) => m.id).toList(growable: false);
    if (_lastMessageIds.length == nextIds.length) {
      var same = true;
      for (var i = 0; i < nextIds.length; i++) {
        if (_lastMessageIds[i] != nextIds[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _lastMessageIds = nextIds;

    if (!mounted) return;
    await _chatController.setMessages(next, animated: false);
  }

  Future<void> _sendText(String text) async {
    final dest = widget.destHashHex.trim().toLowerCase();
    if (dest.isEmpty) return;

    final root = widget.paths.sendDir;
    final dir = Directory('$root${Platform.pathSeparator}$dest');
    await dir.create(recursive: true);

    final fileName = 'msg -- ${_uuid.v4()}.txt';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(text, flush: true);

    await _reload();
  }

  Future<User?> _resolveUser(String id) async {
    if (id == _me.id) return _me;
    if (id == _peer.id) return _peer;
    return User(id: id, name: id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.destHashHex),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Chat(
        currentUserId: _me.id,
        resolveUser: _resolveUser,
        chatController: _chatController,
        onMessageSend: _sendText,
        theme: ChatTheme.fromThemeData(Theme.of(context)),
      ),
    );
  }
}
