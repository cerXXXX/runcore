import 'dart:io';

import '../../../core/platform/runcore_channel.dart';
import '../domain/chat_contact.dart';

class ContactsSnapshot {
  const ContactsSnapshot({
    required this.paths,
    required this.contacts,
    required this.me,
  });

  final RuncorePaths paths;
  final List<ChatContact> contacts;
  final ChatContact? me;
}

class ContactsRepository {
  ContactsRepository({required RuncoreChannel channel}) : _channel = channel;

  final RuncoreChannel _channel;

  Future<ContactsSnapshot> loadSnapshot() async {
    final paths = await _channel.getPaths();
    if (!paths.isValid) {
      throw StateError('Пути пустые: $paths');
    }
    final meName = await _channel.getMeContactName();
    final me = await loadMeContact(paths.contactsDir, meName);
    final contacts = await loadContacts(
      paths.contactsDir,
      meContactName: meName,
    );
    return ContactsSnapshot(paths: paths, contacts: contacts, me: me);
  }

  Future<List<ChatContact>> loadContacts(
    String contactsDir, {
    required String meContactName,
  }) async {
    final out = <ChatContact>[];
    try {
      final d = Directory(contactsDir);
      if (!d.existsSync()) {
        return const [];
      }
      final entries = d
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
      entries.sort((a, b) => a.path.compareTo(b.path));

      for (final dir in entries) {
        final name = _leafName(dir.path);
        if (_isHiddenName(name)) {
          continue;
        }
        if (meContactName.isNotEmpty && name == meContactName) {
          continue;
        }
        out.add(await _readContact(dir.path, name));
      }
    } catch (_) {
      return const [];
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<ChatContact?> loadMeContact(String contactsDir, String meName) async {
    final normalized = meName.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final dirPath = '$contactsDir${Platform.pathSeparator}$normalized';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return null;
    }
    return _readContact(dir.path, normalized);
  }

  static bool _isHiddenName(String name) => name.startsWith('.');

  static String _leafName(String path) =>
      path.split(Platform.pathSeparator).last;

  Future<ChatContact> _readContact(String dirPath, String name) async {
    final lxmfFile = File('$dirPath${Platform.pathSeparator}lxmf');
    final dest = lxmfFile.existsSync()
        ? (await lxmfFile.readAsString().catchError(
            (_) => '',
          )).trim().toLowerCase()
        : '';

    String? avatarPath;
    try {
      final files = Directory(dirPath)
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => _leafName(f.path).toLowerCase().startsWith('avatar.'))
          .toList();
      if (files.isNotEmpty) {
        files.sort((a, b) => a.path.compareTo(b.path));
        avatarPath = files.first.path;
      }
    } catch (_) {}

    return ChatContact(
      name: name,
      destHashHex: dest,
      dirPath: dirPath,
      avatarPath: avatarPath,
    );
  }
}
