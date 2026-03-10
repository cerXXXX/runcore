import 'dart:io';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:uuid/uuid.dart';

import '../../../core/platform/runcore_channel.dart';

class ChatRepository {
  ChatRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  static const String meId = 'me';
  static final RegExp _tsRe = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2})꞉(\d{2})',
  );

  Future<List<Message>> loadMessages({
    required RuncorePaths paths,
    required String destHashHex,
    required String query,
    required String peerId,
  }) async {
    final dest = destHashHex.trim().toLowerCase();
    final q = query.trim().toLowerCase();

    final deliveredDir = '${paths.messagesDir}${Platform.pathSeparator}$dest';
    final sendDir = '${paths.sendDir}${Platform.pathSeparator}$dest';
    final pendingDir =
        '${paths.sendDir}${Platform.pathSeparator}.pending${Platform.pathSeparator}$dest';

    final files = <File>[
      ..._listFiles(deliveredDir),
      ..._listFiles(sendDir),
      ..._listFiles(pendingDir),
    ];

    final next = <Message>[];
    for (final f in files) {
      final name = _leafName(f.path);
      if (name.toLowerCase() == 'caption.txt') {
        continue;
      }

      final createdAt = _guessCreatedAt(name);
      final isPending =
          f.path.startsWith(sendDir) || f.path.startsWith(pendingDir);
      final outbound = _isOutboundByName(name) || isPending;
      final authorId = outbound ? meId : peerId;

      final ext = name.toLowerCase().split('.').last;
      if (ext == 'txt') {
        final text = await f.readAsString().catchError((_) => '');
        if (q.isNotEmpty &&
            !text.toLowerCase().contains(q) &&
            !name.toLowerCase().contains(q)) {
          continue;
        }
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
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) {
        continue;
      }
      next.add(
        Message.file(
          id: f.path,
          authorId: authorId,
          createdAt: createdAt,
          name: name,
          size: size,
          source: f.path,
          status: isPending
              ? MessageStatus.sending
              : (outbound ? MessageStatus.sent : null),
        ),
      );
    }

    next.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final c = at.compareTo(bt);
      if (c != 0) {
        return c;
      }
      return a.id.compareTo(b.id);
    });
    return next;
  }

  Future<void> sendText({
    required RuncorePaths paths,
    required String destHashHex,
    required String text,
  }) async {
    final dest = destHashHex.trim().toLowerCase();
    if (dest.isEmpty) {
      return;
    }

    final dir = Directory('${paths.sendDir}${Platform.pathSeparator}$dest');
    await dir.create(recursive: true);

    final fileName = 'msg -- ${_uuid.v4()}.txt';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(text, flush: true);
  }

  List<File> _listFiles(String dir) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) {
        return const [];
      }
      return d
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => !_leafName(f.path).startsWith('.'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _leafName(String path) => path.split(Platform.pathSeparator).last;

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
        if (num != null) {
          return DateTime.fromMillisecondsSinceEpoch(num);
        }
      }
    }

    return DateTime.now();
  }

  bool _isOutboundByName(String fileName) => fileName.contains(' -- ');
}
