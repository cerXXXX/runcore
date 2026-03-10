import 'dart:io';

import '../../../core/platform/runcore_channel.dart';
import '../domain/chat_contact.dart';

class ContactsSnapshot {
  const ContactsSnapshot({
    required this.paths,
    required this.contacts,
    required this.me,
    required this.interfaces,
    required this.announces,
  });

  final RuncorePaths paths;
  final List<ChatContact> contacts;
  final ChatContact? me;
  final List<RuncoreInterfaceStatus> interfaces;
  final List<RuncoreAnnounce> announces;
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
    final interfaces = await _channel.getInterfaceStats();
    final announces = await _channel.getAnnounces();
    final me = await loadMeContact(paths.contactsDir, meName);
    final contacts = await loadContacts(
      paths.contactsDir,
      meContactName: meName,
    );
    return ContactsSnapshot(
      paths: paths,
      contacts: contacts,
      me: me,
      interfaces: interfaces,
      announces: announces,
    );
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
        final contact = await _readContact(dir.path, name);
        if (contact.destHashHex.isEmpty) {
          continue;
        }
        out.add(contact);
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
    final contact = await _readContact(dir.path, normalized);
    return contact.destHashHex.isEmpty ? null : contact;
  }

  Future<ChatContact?> addContactById(
    String contactsDir,
    String destinationId,
    String? displayName,
  ) async {
    final normalized = destinationId.trim().toLowerCase();
    final validHex = RegExp(r'^[0-9a-f]{32}$');
    if (!validHex.hasMatch(normalized)) {
      throw const FormatException('Неверный LXMF id');
    }

    final requestedName = sanitizeFolderName(displayName ?? '');
    final baseName = requestedName.isEmpty
        ? 'Contact ${normalized.substring(0, 8)}'
        : requestedName;
    final root = Directory(contactsDir);
    if (!root.existsSync()) {
      throw StateError('Каталог контактов не найден');
    }

    var dirPath = '${root.path}${Platform.pathSeparator}$baseName';
    var counter = 2;
    while (Directory(dirPath).existsSync()) {
      final existingLxmf = File('$dirPath${Platform.pathSeparator}lxmf');
      if (existingLxmf.existsSync()) {
        final existing = (await existingLxmf.readAsString().catchError((_) => ''))
            .trim()
            .toLowerCase();
        if (existing == normalized) {
          return _readContact(dirPath, _leafName(dirPath));
        }
      }
      dirPath =
          '${root.path}${Platform.pathSeparator}$baseName $counter';
      counter++;
    }

    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    await File('$dirPath${Platform.pathSeparator}lxmf').writeAsString(
      normalized,
      flush: true,
    );
    return _readContact(dirPath, _leafName(dirPath));
  }

  static bool _isHiddenName(String name) => name.startsWith('.');

  static String sanitizeFolderName(String s) {
    s = s.trim();
    if (s.isEmpty) {
      return '';
    }
    s = s
        .replaceAll(Platform.pathSeparator, '_')
        .replaceAll(':', '_')
        .replaceAll('\u0000', '_');
    if (s.length > 80) {
      s = s.substring(0, 80);
    }
    return s.trim();
  }

  static String _leafName(String path) =>
      path.split(Platform.pathSeparator).last;

  Future<ChatContact> _readContact(String dirPath, String name) async {
    final lxmfFile = File('$dirPath${Platform.pathSeparator}lxmf');
    final dest = lxmfFile.existsSync()
        ? (await lxmfFile.readAsString().catchError(
            (_) => '',
          )).trim().toLowerCase()
        : '';

    final avatarPath = _resolveAvatarPath(dirPath);

    return ChatContact(
      name: name,
      destHashHex: dest,
      dirPath: dirPath,
      avatarPath: avatarPath,
    );
  }

  String? _resolveAvatarPath(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        return null;
      }

      final files = dir.listSync(followLinks: false).whereType<File>().toList();
      if (files.isEmpty) {
        return null;
      }

      const preferredNames = [
        'avatar.png',
        'avatar.jpg',
        'avatar.jpeg',
        'avatar.heic',
        'avatar.heif',
        'avatar.webp',
        'avatar.gif',
        'avatar.bmp',
        'avatar.tiff',
        'avatar.bin',
      ];

      final byName = <String, File>{};
      for (final file in files) {
        byName[_leafName(file.path).toLowerCase()] = file;
      }

      for (final name in preferredNames) {
        final file = byName[name];
        if (file == null) {
          continue;
        }
        final stat = file.statSync();
        if (stat.size > 0) {
          return file.path;
        }
      }

      final genericCandidates =
          files
              .where(
                (f) => _leafName(f.path).toLowerCase().startsWith('avatar'),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in genericCandidates) {
        final stat = file.statSync();
        if (stat.size > 0) {
          return file.path;
        }
      }
    } catch (_) {}
    return null;
  }
}
