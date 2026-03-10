import 'dart:convert';

import 'package:flutter/services.dart';

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

  bool get isValid =>
      contactsDir.isNotEmpty && sendDir.isNotEmpty && messagesDir.isNotEmpty;
}

class RuncoreInterfaceStatus {
  const RuncoreInterfaceStatus({
    required this.name,
    required this.shortName,
    required this.type,
    required this.online,
  });

  final String name;
  final String shortName;
  final String type;
  final bool online;

  String get displayName => shortName.isNotEmpty ? shortName : name;
}

class RuncoreAnnounce {
  const RuncoreAnnounce({
    required this.destinationHashHex,
    required this.displayName,
    required this.lastSeen,
  });

  final String destinationHashHex;
  final String displayName;
  final int lastSeen;

  String get title =>
      displayName.trim().isEmpty ? destinationHashHex : displayName.trim();
}

class RuncoreChannel {
  RuncoreChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('runcore');

  final MethodChannel _channel;

  Future<RuncorePaths> getPaths() async {
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

  Future<String> getMeContactName() async {
    final res = await _channel.invokeMethod<String>('getMeContactName');
    return (res ?? '').trim();
  }

  Future<String?> pickImagePath() async {
    final res = await _channel.invokeMethod<String>('pickImagePath');
    final v = (res ?? '').trim();
    return v.isEmpty ? null : v;
  }

  Future<void> setDisplayName(String name) async {
    await _channel.invokeMethod<void>('setDisplayName', name);
  }

  Future<List<RuncoreInterfaceStatus>> getInterfaceStats() async {
    final res = await _channel.invokeMethod<String>('getInterfaceStats');
    final raw = (res ?? '').trim();
    if (raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const [];
      }
      final entries = decoded['interfaces'];
      if (entries is! List) {
        return const [];
      }
      return entries
          .whereType<Map>()
          .map((item) {
            final status = item['status'];
            final online = status is bool
                ? status
                : (item['online'] as bool?) ?? false;
            return RuncoreInterfaceStatus(
              name: (item['name'] as String?)?.trim() ?? '',
              shortName: (item['short_name'] as String?)?.trim() ?? '',
              type: (item['type'] as String?)?.trim() ?? '',
              online: online,
            );
          })
          .where((item) => item.name.isNotEmpty || item.shortName.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<RuncoreAnnounce>> getAnnounces() async {
    final res = await _channel.invokeMethod<String>('getAnnounces');
    final raw = (res ?? '').trim();
    if (raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map
          ? (decoded['announces'] as List?) ?? const []
          : const [];
      return list
          .whereType<Map>()
          .map(
            (item) => RuncoreAnnounce(
              destinationHashHex:
                  (item['destination_hash_hex'] as String?)?.trim() ?? '',
              displayName: (item['display_name'] as String?)?.trim() ?? '',
              lastSeen: (item['last_seen'] as num?)?.toInt() ?? 0,
            ),
          )
          .where((item) => item.destinationHashHex.isNotEmpty)
          .toList(growable: true)
        ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    } catch (_) {
      return const [];
    }
  }
}
